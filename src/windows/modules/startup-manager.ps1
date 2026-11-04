# Gerenciador de Inicialização compatível com o Gerenciador de Tarefas do Windows (StartupApproved)

#region dev-only
if (-not (Get-Command Write-OptimizerLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\core\logger.ps1')
}
#endregion

function Get-OptiKitStartupItems {
    [CmdletBinding()]
    param()

    $sources = @(
        @{
            Scope        = 'Usuário (HKCU Run)'
            RunPath      = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
            ApprovedPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
            Kind         = 'Registry'
        },
        @{
            Scope        = 'Sistema (HKLM Run)'
            RunPath      = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            ApprovedPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
            Kind         = 'Registry'
        },
        @{
            Scope        = 'Sistema 32-bit (WOW64)'
            RunPath      = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
            ApprovedPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
            Kind         = 'Registry'
        },
        @{
            Scope        = 'Pasta Inicializar (Usuário)'
            FolderPath   = [Environment]::GetFolderPath('Startup')
            ApprovedPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
            Kind         = 'Folder'
        }
    )

    $items = New-Object 'System.Collections.Generic.List[pscustomobject]'

    foreach ($src in $sources) {
        if ($src.Kind -eq 'Registry') {
            if (-not (Test-Path -LiteralPath $src.RunPath)) { continue }
            $regKey = Get-Item -LiteralPath $src.RunPath -ErrorAction SilentlyContinue
            if (-not $regKey) { continue }

            $appKey = if (Test-Path -LiteralPath $src.ApprovedPath) { Get-Item -LiteralPath $src.ApprovedPath -ErrorAction SilentlyContinue } else { $null }

            foreach ($valName in $regKey.GetValueNames()) {
                if ([string]::IsNullOrWhiteSpace($valName)) { continue }
                $cmd = [string]$regKey.GetValue($valName, '')
                $enabled = $true

                if ($appKey -and (@($appKey.GetValueNames()) -contains $valName)) {
                    $bytes = $appKey.GetValue($valName, $null)
                    if ($bytes -is [byte[]] -and $bytes.Length -ge 1) {
                        # Odd first byte (0x01, 0x03) = Disabled by Task Manager
                        $enabled = (($bytes[0] -band 1) -eq 0)
                    }
                }

                $isProt = ($valName -match '(?i)(Riot Vanguard|vgtray|SecurityHealth)') -or ($cmd -match '(?i)(vgtray\.exe|SecurityHealthSystray\.exe)')
                [void]$items.Add([pscustomobject]@{
                    Name         = $valName
                    Command      = $cmd
                    Scope        = $src.Scope
                    ApprovedPath = $src.ApprovedPath
                    Enabled      = $enabled
                    StatusText   = if ($enabled) { 'Ativado' } else { 'Desativado' }
                    IsProtected  = $isProt
                })
            }
        }
        elseif ($src.Kind -eq 'Folder') {
            if (-not $src.FolderPath -or -not (Test-Path -LiteralPath $src.FolderPath)) { continue }
            $files = Get-ChildItem -LiteralPath $src.FolderPath -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne 'desktop.ini' }
            $appKey = if (Test-Path -LiteralPath $src.ApprovedPath) { Get-Item -LiteralPath $src.ApprovedPath -ErrorAction SilentlyContinue } else { $null }

            foreach ($f in $files) {
                $enabled = $true
                if ($appKey -and (@($appKey.GetValueNames()) -contains $f.Name)) {
                    $bytes = $appKey.GetValue($f.Name, $null)
                    if ($bytes -is [byte[]] -and $bytes.Length -ge 1) {
                        $enabled = (($bytes[0] -band 1) -eq 0)
                    }
                }

                [void]$items.Add([pscustomobject]@{
                    Name         = $f.Name
                    Command      = $f.FullName
                    Scope        = $src.Scope
                    ApprovedPath = $src.ApprovedPath
                    Enabled      = $enabled
                    StatusText   = if ($enabled) { 'Ativado' } else { 'Desativado' }
                    IsProtected  = $false
                })
            }
        }
    }

    return $items.ToArray()
}

function Set-OptiKitStartupItemState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Item,

        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )

    if ($Item.IsProtected -and -not $Enabled) {
        $msg = "O item de inicialização '$($Item.Name)' pertence ao sistema de segurança/anti-cheat e foi preservado."
        Write-OptimizerLog -Level WARN -Message $msg
        return $false
    }

    $actionLabel = if ($Enabled) { 'Ativar' } else { 'Desativar' }
    Invoke-Mutation -Description ("{0} item de inicialização '{1}' ({2})" -f $actionLabel, $Item.Name, $Item.Scope) -Action {
        if (-not (Test-Path -LiteralPath $Item.ApprovedPath)) {
            New-Item -Path $Item.ApprovedPath -Force -ErrorAction Stop | Out-Null
        }

        if ($Enabled) {
            $bytes = [byte[]](0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
        }
        else {
            $ft = [BitConverter]::GetBytes([DateTime]::UtcNow.ToFileTime())
            $bytes = [byte[]](0x03, 0x00, 0x00, 0x00) + $ft
        }

        Set-ItemProperty -LiteralPath $Item.ApprovedPath -Name $Item.Name -Value $bytes -Type Binary -Force -ErrorAction Stop
    } | Out-Null

    return $true
}
