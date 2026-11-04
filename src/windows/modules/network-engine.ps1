# Motor de Rede: DNS over HTTPS (Windows 11+) com captura de DNS original e Undo via state.json

#region dev-only
if (-not (Get-Command Write-OptimizerLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\core\logger.ps1')
}
if (-not (Get-Command Get-OptiKitHardware -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'hardware-utils.ps1')
}
if (-not (Get-Command Invoke-NativeStep -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'maintenance.ps1')
}
#endregion

function Get-OptiKitDohProviders {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject]@{
            Key        = 'Cloudflare'
            Name       = 'Cloudflare (1.1.1.1 / 1.0.0.1)'
            Primary    = '1.1.1.1'
            Secondary  = '1.0.0.1'
            Primary6   = '2606:4700:4700::1111'
            Secondary6 = '2606:4700:4700::1001'
            Template   = 'https://cloudflare-dns.com/dns-query'
        },
        [pscustomobject]@{
            Key        = 'Google'
            Name       = 'Google (8.8.8.8 / 8.8.4.4)'
            Primary    = '8.8.8.8'
            Secondary  = '8.8.4.4'
            Primary6   = '2001:4860:4860::8888'
            Secondary6 = '2001:4860:4860::8844'
            Template   = 'https://dns.google/dns-query'
        },
        [pscustomobject]@{
            Key        = 'Quad9'
            Name       = 'Quad9 (9.9.9.9 / 149.112.112.112)'
            Primary    = '9.9.9.9'
            Secondary  = '149.112.112.112'
            Primary6   = '2620:fe::fe'
            Secondary6 = '2620:fe::9'
            Template   = 'https://dns.quad9.net/dns-query'
        },
        [pscustomobject]@{
            Key        = 'AdGuard'
            Name       = 'AdGuard DNS (94.140.14.14 / 94.140.15.15)'
            Primary    = '94.140.14.14'
            Secondary  = '94.140.15.15'
            Primary6   = '2a10:50c0::ad1:ff'
            Secondary6 = '2a10:50c0::ad2:ff'
            Template   = 'https://dns.adguard-dns.com/dns-query'
        }
    )
}

function Test-OptiKitDohSupported {
    [CmdletBinding()]
    param(
        [pscustomobject]$Hardware
    )

    if (-not $Hardware) {
        $Hardware = Get-OptiKitHardware
    }

    return ([bool]$Hardware.IsWin11 -and [int]$Hardware.OsBuild -ge 22000)
}

function Get-OptiKitDnsAdapters {
    [CmdletBinding()]
    param()

    $results = New-Object 'System.Collections.Generic.List[pscustomobject]'
    if (-not (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue)) {
        return $results.ToArray()
    }

    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
    foreach ($adapter in $adapters) {
        $ipv4Servers = @()
        $ipv6Servers = @()
        if (Get-Command Get-DnsClientServerAddress -ErrorAction SilentlyContinue) {
            $v4Info = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $ipv4Servers = @($v4Info | ForEach-Object { @($_.ServerAddresses) } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            $v6Info = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue
            $ipv6Servers = @($v6Info | ForEach-Object { @($_.ServerAddresses) } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        }

        $dhcpV4 = $false
        $dhcpV6 = $false
        if (Get-Command Get-NetIPInterface -ErrorAction SilentlyContinue) {
            $v4Interface = Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            if ($v4Interface) { $dhcpV4 = ([string]$v4Interface.Dhcp -eq 'Enabled') }
            $v6Interface = Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue
            if ($v6Interface) { $dhcpV6 = ([string]$v6Interface.Dhcp -eq 'Enabled') }
        }

        [void]$results.Add([pscustomobject]@{
            InterfaceIndex = [int]$adapter.ifIndex
            Name           = [string]$adapter.Name
            IPv4Servers    = $ipv4Servers
            IPv6Servers    = $ipv6Servers
            DhcpV4         = $dhcpV4
            DhcpV6         = $dhcpV6
        })
    }

    return $results.ToArray()
}

function Set-OptiKitDnsFamily {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$AdapterName,
        [Parameter(Mandatory = $true)][ValidateSet('ipv4', 'ipv6')][string]$Family,
        [Parameter(Mandatory = $true)][ValidateSet('dhcp', 'static')][string]$Mode,
        [string[]]$Servers = @()
    )

    $nameArg = ("name=`"{0}`"" -f $AdapterName)
    $stepPrefix = "DNS {0} ({1})" -f $Family, $AdapterName
    $cleanServers = @($Servers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

    if ($Mode -eq 'dhcp' -or $cleanServers.Count -eq 0) {
        Invoke-NativeStep -FilePath 'netsh.exe' -ArgumentList @('interface', $Family, 'set', 'dnsservers', $nameArg, 'source=dhcp') -StepName $stepPrefix
        return
    }

    Invoke-NativeStep -FilePath 'netsh.exe' -ArgumentList @(
        'interface', $Family, 'set', 'dnsservers', $nameArg,
        'source=static', ("address={0}" -f $cleanServers[0]), 'register=primary', 'validate=no'
    ) -StepName $stepPrefix

    for ($index = 1; $index -lt $cleanServers.Count; $index++) {
        Invoke-NativeStep -FilePath 'netsh.exe' -ArgumentList @(
            'interface', $Family, 'add', 'dnsservers', $nameArg,
            ("address={0}" -f $cleanServers[$index]), ("index={0}" -f ($index + 1)), 'validate=no'
        ) -StepName $stepPrefix
    }
}

function Remove-OptiKitDohEncryption {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Server
    )

    Start-Process -FilePath 'netsh.exe' -ArgumentList @('dnsclient', 'delete', 'encryption', ("server={0}" -f $Server), 'protocol=doh') -NoNewWindow -Wait -PassThru | Out-Null
}

function Set-OptiKitDohEncryption {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$Template
    )

    # Remove uma entrada anterior do mesmo IP para manter a operação idempotente.
    Remove-OptiKitDohEncryption -Server $Server
    Invoke-NativeStep -FilePath 'netsh.exe' -ArgumentList @(
        'dnsclient', 'add', 'encryption',
        ("server={0}" -f $Server),
        ("dohtemplate={0}" -f $Template),
        'autoupgrade=yes',
        'udpfallback=no'
    ) -StepName ("DoH {0}" -f $Server)
}

function Set-OptiKitDohProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProviderKey
    )

    $provider = Get-OptiKitDohProviders | Where-Object { $_.Key -eq $ProviderKey } | Select-Object -First 1
    if (-not $provider) {
        throw ("Provedor de DoH desconhecido: {0}" -f $ProviderKey)
    }

    if (-not (Test-OptiKitDohSupported)) {
        throw 'DNS over HTTPS nativo requer Windows 11 (build 22000+). Nenhuma alteração foi feita.'
    }

    $adapters = @(Get-OptiKitDnsAdapters)
    if ($adapters.Count -eq 0) {
        throw 'Nenhum adaptador físico ativo com DNS IPv4/IPv6 foi encontrado para configurar o DoH.'
    }

    $capturedItems = New-Object 'System.Collections.Generic.List[hashtable]'
    foreach ($adapter in $adapters) {
        [void]$capturedItems.Add(@{
            kind           = 'dns'
            interfaceIndex = [int]$adapter.InterfaceIndex
            adapterName    = [string]$adapter.Name
            dhcpV4         = [bool]$adapter.DhcpV4
            dhcpV6         = [bool]$adapter.DhcpV6
            ipv4           = @($adapter.IPv4Servers)
            ipv6           = @($adapter.IPv6Servers)
        })
    }

    Save-CapturedState -Id 'DnsOverHttps' -CapturedItems $capturedItems.ToArray()

    Invoke-Mutation -Description ("Configurar DNS over HTTPS ({0})" -f $provider.Name) -Action {
        foreach ($adapter in $adapters) {
            Set-OptiKitDnsFamily -AdapterName $adapter.Name -Family 'ipv4' -Mode 'static' -Servers @($provider.Primary, $provider.Secondary)
            Write-OptimizerLog -Level INFO -Message ("DNS IPv4 de '{0}' definido como {1} / {2}." -f $adapter.Name, $provider.Primary, $provider.Secondary)

            try {
                Set-OptiKitDnsFamily -AdapterName $adapter.Name -Family 'ipv6' -Mode 'static' -Servers @($provider.Primary6, $provider.Secondary6)
                Write-OptimizerLog -Level INFO -Message ("DNS IPv6 de '{0}' definido como {1} / {2}." -f $adapter.Name, $provider.Primary6, $provider.Secondary6)
            }
            catch {
                Write-OptimizerLog -Level WARN -Message ("Não foi possível definir DNS IPv6 em '{0}' (IPv6 desativado?): {1}" -f $adapter.Name, $_.Exception.Message)
            }
        }

        foreach ($server in @($provider.Primary, $provider.Secondary, $provider.Primary6, $provider.Secondary6)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$server)) {
                Set-OptiKitDohEncryption -Server $server -Template $provider.Template
            }
        }

        Write-OptimizerLog -Level OK -Message ("DoH ativo via {0}. Verifique em Configurações > Rede e Internet > DNS." -f $provider.Name)
    } | Out-Null
}

function Restore-OptiKitDns {
    [CmdletBinding()]
    param()

    $capturedRecord = Get-CapturedState -Id 'DnsOverHttps'
    if (-not $capturedRecord -or -not $capturedRecord.captured) {
        throw 'Nenhum estado de DNS capturado para reverter.'
    }

    Invoke-Mutation -Description 'Restaurar configuração de DNS original' -Action {
        foreach ($item in @($capturedRecord.captured)) {
            if ($item.kind -ne 'dns') { continue }

            $modeV4 = if ([bool]$item.dhcpV4) { 'dhcp' } else { 'static' }
            Set-OptiKitDnsFamily -AdapterName $item.adapterName -Family 'ipv4' -Mode $modeV4 -Servers @($item.ipv4)
            Write-OptimizerLog -Level INFO -Message ("DNS IPv4 de '{0}' restaurado ({1})." -f $item.adapterName, $modeV4)

            $modeV6 = if ([bool]$item.dhcpV6) { 'dhcp' } else { 'static' }
            try {
                Set-OptiKitDnsFamily -AdapterName $item.adapterName -Family 'ipv6' -Mode $modeV6 -Servers @($item.ipv6)
                Write-OptimizerLog -Level INFO -Message ("DNS IPv6 de '{0}' restaurado ({1})." -f $item.adapterName, $modeV6)
            }
            catch {
                Write-OptimizerLog -Level WARN -Message ("Falha ao restaurar DNS IPv6 de '{0}': {1}" -f $item.adapterName, $_.Exception.Message)
            }
        }

        foreach ($provider in Get-OptiKitDohProviders) {
            foreach ($server in @($provider.Primary, $provider.Secondary, $provider.Primary6, $provider.Secondary6)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$server)) {
                    Remove-OptiKitDohEncryption -Server $server
                }
            }
        }

        Write-OptimizerLog -Level OK -Message 'Configuração de DNS restaurada e templates DoH do OptiKit removidos.'
    } | Out-Null

    Remove-CapturedState -Id 'DnsOverHttps'
}
