# Testes dos diagnósticos somente leitura: BIOS/TPM, disco, estabilidade, reboot pendente e Defender

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'src\windows\core\logger.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\core\backup.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\hardware-utils.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\winget-engine.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\tweak-engine.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\maintenance.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\diagnostics.ps1')
}

Describe 'Diagnósticos estendidos (diagnostics.ps1)' {
    BeforeEach {
        $testRoot = Join-Path $TestDrive ("diagnostics_test_" + [Guid]::NewGuid().ToString('N'))
        Initialize-OptiKitEnvironment -DataRoot $testRoot -DryRun:$false | Out-Null
    }

    It 'Deve reportar BIOS/UEFI, Secure Boot e TPM' {
        Mock Get-CimInstance {
            if ($ClassName -eq 'Win32_BIOS') {
                [pscustomobject]@{ Manufacturer = 'ASUS'; SMBIOSBIOSVersion = '1.2.3'; ReleaseDate = [datetime]'2025-01-01' }
            }
            elseif ($ClassName -eq 'Win32_ComputerSystem') {
                [pscustomobject]@{ Manufacturer = 'ASUS'; Model = 'ROG X670E' }
            }
        }
        Mock Confirm-SecureBootUEFI { $true }
        Mock Get-Tpm { [pscustomobject]@{ TpmPresent = $true; TpmReady = $true; SpecVersion = '2.0' } }

        $item = Get-OptiKitDiagnosticBios
        $item.Status | Should -Be 'OK'
        $item.Summary | Should -Match 'Secure Boot ativo'
        $item.Summary | Should -Match 'TPM 2.0 pronto'
        $item.Detail | Should -Match 'BIOS 1.2.3'
    }

    It 'Deve avisar quando Secure Boot ou TPM não está pronto' {
        Mock Get-CimInstance {
            if ($ClassName -eq 'Win32_BIOS') { [pscustomobject]@{ Manufacturer = 'ASUS'; SMBIOSBIOSVersion = '1.2.3'; ReleaseDate = [datetime]'2025-01-01' } }
            elseif ($ClassName -eq 'Win32_ComputerSystem') { [pscustomobject]@{ Manufacturer = 'ASUS'; Model = 'ROG X670E' } }
        }
        Mock Confirm-SecureBootUEFI { $false }
        Mock Get-Tpm { [pscustomobject]@{ TpmPresent = $false; TpmReady = $false; SpecVersion = '2.0' } }

        $item = Get-OptiKitDiagnosticBios
        $item.Status | Should -Be 'Warn'
        $item.Summary | Should -Match 'Secure Boot desativado'
        $item.Summary | Should -Match 'TPM ausente'
    }

    It 'Deve reportar saúde e desgaste dos discos' {
        $disks = @([pscustomobject]@{
            FriendlyName      = 'NVMe Teste'
            MediaType         = 'SSD'
            HealthStatus      = 'Healthy'
            OperationalStatus = 'OK'
            Size              = 500GB
            DeviceId          = '0'
        })

        $item = Get-OptiKitDiagnosticDisk -Disks $disks -ReliabilityCounters @{ '0' = [pscustomobject]@{ Wear = 12 } } -SystemVolume ([pscustomobject]@{ SizeRemaining = 100GB; Size = 500GB })
        $item.Status | Should -Be 'OK'
        $item.Detail | Should -Match 'NVMe Teste'
        $item.Detail | Should -Match 'desgaste 12%'
    }

    It 'Deve avisar quando o SSD está muito desgastado' {
        $disks = @([pscustomobject]@{
            FriendlyName      = 'SSD Antigo'
            MediaType         = 'SSD'
            HealthStatus      = 'Healthy'
            OperationalStatus = 'OK'
            Size              = 240GB
            DeviceId          = '0'
        })

        $item = Get-OptiKitDiagnosticDisk -Disks $disks -ReliabilityCounters @{ '0' = [pscustomobject]@{ Wear = 90 } } -SystemVolume ([pscustomobject]@{ SizeRemaining = 100GB; Size = 500GB })
        $item.Status | Should -Be 'Warn'
        $item.Summary | Should -Match 'desgaste 90%'
    }

    It 'Deve reportar erros WHEA como problema de estabilidade' {
        Mock Get-WinEvent {
            if ($FilterHashtable.ProviderName -eq 'Microsoft-Windows-WHEA-Logger') {
                @([pscustomobject]@{ TimeCreated = Get-Date })
            }
            else {
                @()
            }
        }

        $item = Get-OptiKitDiagnosticStability
        $item.Status | Should -Be 'Error'
        $item.Summary | Should -Match 'WHEA'
    }

    It 'Deve detectar reinicialização pendente' {
        Mock Test-Path { $true }
        Mock Get-ItemProperty { $null }

        $item = Get-OptiKitDiagnosticPendingReboot
        $item.Status | Should -Be 'Warn'
        $item.Detail | Should -Match 'Windows Update'
    }

    It 'Deve reportar Defender ativo e atualizado' {
        Mock Get-MpComputerStatus {
            [pscustomobject]@{ AntivirusEnabled = $true; RealTimeProtectionEnabled = $true; AntivirusSignatureAge = 2 }
        }

        $item = Get-OptiKitDiagnosticDefender
        $item.Status | Should -Be 'OK'
        $item.Detail | Should -Match 'Assinaturas com 2 dia'
    }
}
