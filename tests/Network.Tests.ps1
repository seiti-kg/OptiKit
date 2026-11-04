# Testes do motor de rede: provedores DoH, gate de Windows 11, captura/restauração de DNS

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'src\windows\core\logger.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\core\backup.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\hardware-utils.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\winget-engine.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\tweak-engine.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\maintenance.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\network-engine.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\core\state-checker.ps1')
}

Describe 'Network Engine (network-engine.ps1)' {
    BeforeEach {
        $testRoot = Join-Path $TestDrive ("network_test_" + [Guid]::NewGuid().ToString('N'))
        Initialize-OptiKitEnvironment -DataRoot $testRoot -DryRun:$false | Out-Null
        $script:OptiKitHardwareCache = [pscustomobject]@{
            CpuName         = 'Fake Win11'
            CpuCores        = 8
            IsX3D           = $false
            IsX3DDualCcd    = $false
            IsLaptop        = $false
            GpuNames        = @()
            GpuVendors      = @()
            SystemDiskIsSSD = $true
            OsBuild         = 22621
            IsWin11         = $true
            Summary         = 'fake'
        }

        Mock Get-OptiKitDnsAdapters {
            @([pscustomobject]@{
                InterfaceIndex = 7
                Name           = 'Ethernet'
                IPv4Servers    = @('192.168.1.1', '192.168.1.2')
                IPv6Servers    = @('fe80::1')
                DhcpV4         = $false
                DhcpV6         = $false
            })
        }
        Mock Invoke-NativeStep {}
        Mock Remove-OptiKitDohEncryption {}
    }

    It 'Deve expor provedores DoH conhecidos com templates HTTPS' {
        $providers = @(Get-OptiKitDohProviders)
        $providers.Count | Should -BeGreaterOrEqual 4
        $providers.Key | Should -Contain 'Cloudflare'
        foreach ($provider in $providers) {
            $provider.Primary | Should -Match '^\d+\.\d+\.\d+\.\d+$'
            $provider.Secondary | Should -Match '^\d+\.\d+\.\d+\.\d+$'
            $provider.Template | Should -Match '^https://'
        }
    }

    It 'Deve exigir Windows 11 para DoH nativo' {
        (Test-OptiKitDohSupported -Hardware ([pscustomobject]@{ IsWin11 = $false; OsBuild = 19045 })) | Should -BeFalse
        (Test-OptiKitDohSupported -Hardware ([pscustomobject]@{ IsWin11 = $true; OsBuild = 22621 })) | Should -BeTrue
    }

    It 'Deve aplicar DoH, capturar o DNS original e restaurar no Undo' {
        Set-OptiKitDohProvider -ProviderKey 'Cloudflare'

        Should -Invoke Invoke-NativeStep -Times 1 -Exactly -ParameterFilter {
            ($ArgumentList -contains 'ipv4') -and ($ArgumentList -contains 'source=static') -and ($ArgumentList -contains 'address=1.1.1.1')
        }
        Should -Invoke Invoke-NativeStep -Times 1 -Exactly -ParameterFilter {
            ($ArgumentList -contains 'ipv4') -and ($ArgumentList -contains 'add') -and ($ArgumentList -contains 'address=1.0.0.1')
        }
        Should -Invoke Invoke-NativeStep -Times 1 -Exactly -ParameterFilter {
            ($ArgumentList -contains 'ipv6') -and ($ArgumentList -contains 'address=2606:4700:4700::1111')
        }
        Should -Invoke Invoke-NativeStep -Times 1 -Exactly -ParameterFilter {
            ($ArgumentList -contains 'dnsclient') -and ($ArgumentList -contains 'encryption') -and ($ArgumentList -contains 'server=1.1.1.1')
        }
        Should -Invoke Remove-OptiKitDohEncryption -Times 4 -Exactly

        $captured = Get-CapturedState -Id 'DnsOverHttps'
        @($captured.captured).Count | Should -Be 1
        @($captured.captured[0].ipv4) | Should -Contain '192.168.1.1'
        @($captured.captured[0].ipv6) | Should -Contain 'fe80::1'

        Restore-OptiKitDns

        Should -Invoke Invoke-NativeStep -Times 1 -Exactly -ParameterFilter {
            ($ArgumentList -contains 'ipv4') -and ($ArgumentList -contains 'source=static') -and ($ArgumentList -contains 'address=192.168.1.1')
        }
        Should -Invoke Invoke-NativeStep -Times 1 -Exactly -ParameterFilter {
            ($ArgumentList -contains 'ipv6') -and ($ArgumentList -contains 'address=fe80::1')
        }
        Should -Invoke Remove-OptiKitDohEncryption -Times 20 -Exactly
        (Get-CapturedState -Id 'DnsOverHttps') | Should -BeNullOrEmpty
    }

    It 'Deve restaurar DHCP quando o adaptador usava DNS dinâmico' {
        Mock Get-OptiKitDnsAdapters {
            @([pscustomobject]@{
                InterfaceIndex = 9
                Name           = 'Wi-Fi'
                IPv4Servers    = @('192.168.0.1')
                IPv6Servers    = @()
                DhcpV4         = $true
                DhcpV6         = $true
            })
        }

        Set-OptiKitDohProvider -ProviderKey 'Quad9'
        Restore-OptiKitDns

        Should -Invoke Invoke-NativeStep -Times 1 -Exactly -ParameterFilter {
            ($ArgumentList -contains 'ipv4') -and ($ArgumentList -contains 'source=dhcp')
        }
        Should -Invoke Invoke-NativeStep -Times 1 -Exactly -ParameterFilter {
            ($ArgumentList -contains 'ipv6') -and ($ArgumentList -contains 'source=dhcp')
        }
    }

    It 'Deve recusar DoH em Windows 10 sem capturar estado' {
        $script:OptiKitHardwareCache = [pscustomobject]@{
            CpuName         = 'Fake Win10'
            CpuCores        = 8
            IsX3D           = $false
            IsX3DDualCcd    = $false
            IsLaptop        = $false
            GpuNames        = @()
            GpuVendors      = @()
            SystemDiskIsSSD = $true
            OsBuild         = 19045
            IsWin11         = $false
            Summary         = 'fake'
        }

        { Set-OptiKitDohProvider -ProviderKey 'Cloudflare' } | Should -Throw '*Windows 11*'
        (Get-CapturedState -Id 'DnsOverHttps') | Should -BeNullOrEmpty
    }
}

