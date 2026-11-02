# Motor de Perfis de Jogos (VALORANT, Detecção de Executável, FSO/DPI, GPU Preference, NIC Anti-Jitter, Shader Cache)

#region dev-only
if (-not (Get-Command Write-OptimizerLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\core\logger.ps1')
}
if (-not (Get-Command Save-CapturedState -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\core\backup.ps1')
}
if (-not (Get-Command Optimize-UsbPower -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'hardware-utils.ps1')
}
if (-not (Get-Command Set-RegistryEntryValue -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'tweak-engine.ps1')
}
#endregion

$script:AllowedGameActions = @(
    'Set-AppCompatFlags',
    'Set-DirectXGpuPreference',
    'Optimize-NetworkAdapterGaming',
    'Disable-RiotClientStartup',
    'Clear-ShaderCache',
    'Optimize-UsbPower'
)

function Find-GameExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$ProfileConfig,

        [string]$RiotInstallsPath
    )

    $det = $ProfileConfig.executableDetection
    if (-not $det) {
        return $null
    }

    foreach ($candidate in @($det.defaultPaths)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($det.registryFallback)) {
        try {
            if (Test-Path -LiteralPath $det.registryFallback) {
                $props = Get-ItemProperty -LiteralPath $det.registryFallback -ErrorAction SilentlyContinue
                if ($props -and $props.InstallLocation) {
                    $baseLoc = $props.InstallLocation.Trim('"')
                    $exeFromReg = Join-Path $baseLoc 'ShooterGame\Binaries\Win64\VALORANT-Win64-Shipping.exe'
                    if (Test-Path -LiteralPath $exeFromReg) {
                        return $exeFromReg
                    }
                    $directExe = Get-ChildItem -Path $baseLoc -Filter '*-Win64-Shipping.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($directExe) {
                        return $directExe.FullName
                    }
                }
            }
        }
        catch {
            Write-Verbose ("Erro no fallback de registro para jogo: {0}" -f $_.Exception.Message)
        }
    }

    if (-not $RiotInstallsPath) {
        $RiotInstallsPath = Join-Path $env:ProgramData 'Riot Games\RiotClientInstalls.json'
    }

    if (Test-Path -LiteralPath $RiotInstallsPath) {
        try {
            $riotJson = [System.IO.File]::ReadAllText($RiotInstallsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($riotJson -and $riotJson.associated_client) {
                foreach ($prop in $riotJson.associated_client.PSObject.Properties) {
                    $installDir = ($prop.Name -replace '/', '\').TrimEnd('\')
                    if ($installDir -match '(?i)VALORANT') {
                        $candidateExe = Join-Path $installDir 'ShooterGame\Binaries\Win64\VALORANT-Win64-Shipping.exe'
                        if (Test-Path -LiteralPath $candidateExe) {
                            return $candidateExe
                        }
                    }
                }
            }
        }
        catch {
            Write-Verbose ("Erro ao ler RiotClientInstalls.json: {0}" -f $_.Exception.Message)
        }
    }

    return $null
}

function Set-AppCompatFlags {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExecutablePath,

        [string]$Flags = '~ DISABLEDXMAXIMIZEDWINDOWEDMODE HIGHDPIAWARE',

        [string]$StateKey = 'Val_FSO_HighDPI',

        [ValidateSet('Apply', 'Undo')]
        [string]$Mode = 'Apply'
    )

    $layersKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    if ($Mode -eq 'Apply') {
        $cur = Get-RegistryEntryState -Path $layersKey -Name $ExecutablePath -FallbackType 'String'
        Save-CapturedState -Id $StateKey -CapturedItems @(
            @{ kind = 'registry'; path = $layersKey; name = $ExecutablePath; existed = $cur.ValueExisted; type = 'String'; value = $cur.Value }
        )
        Set-RegistryEntryValue -Path $layersKey -Name $ExecutablePath -Type 'String' -Value $Flags
    }
    else {
        $cap = Get-CapturedState -Id $StateKey
        if ($cap -and $cap.captured -and $cap.captured.Count -gt 0 -and $cap.captured[0].existed) {
            Set-RegistryEntryValue -Path $layersKey -Name $ExecutablePath -Type 'String' -Value $cap.captured[0].value
        }
        else {
            Set-RegistryEntryValue -Path $layersKey -Name $ExecutablePath -Type 'String' -Value '<RemoveEntry>'
        }
        Remove-CapturedState -Id $StateKey
    }
}

function Set-DirectXGpuPreference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExecutablePath,

        [string]$StateKey = 'Val_DirectX_HighPerf',

        [ValidateSet('Apply', 'Undo')]
        [string]$Mode = 'Apply'
    )

    $gpuKey = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    $prefVal = 'GpuPreference=2;'

    if ($Mode -eq 'Apply') {
        $cur = Get-RegistryEntryState -Path $gpuKey -Name $ExecutablePath -FallbackType 'String'
        Save-CapturedState -Id $StateKey -CapturedItems @(
            @{ kind = 'registry'; path = $gpuKey; name = $ExecutablePath; existed = $cur.ValueExisted; type = 'String'; value = $cur.Value }
        )
        Set-RegistryEntryValue -Path $gpuKey -Name $ExecutablePath -Type 'String' -Value $prefVal
    }
    else {
        $cap = Get-CapturedState -Id $StateKey
        if ($cap -and $cap.captured -and $cap.captured.Count -gt 0 -and $cap.captured[0].existed) {
            Set-RegistryEntryValue -Path $gpuKey -Name $ExecutablePath -Type 'String' -Value $cap.captured[0].value
        }
        else {
            Set-RegistryEntryValue -Path $gpuKey -Name $ExecutablePath -Type 'String' -Value '<RemoveEntry>'
        }
        Remove-CapturedState -Id $StateKey
    }
}

function Optimize-NetworkAdapterGaming {
    [CmdletBinding()]
    param(
        [ValidateSet('Apply', 'Undo')]
        [string]$Mode = 'Apply'
    )

    $stateKey = 'NetworkAdapterGaming'
    $targetKeywords = @(
        '*EEE',
        'EEELinkAdvertisement',
        'AdvancedEEE',
        'GreenEthernet',
        'EnableGreenEthernet',
        'PowerSavingMode'
    )

    if ($Mode -eq 'Apply') {
        $capturedProps = New-Object 'System.Collections.Generic.List[hashtable]'
        if (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) {
            $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
            foreach ($nic in $adapters) {
                $advProps = Get-NetAdapterAdvancedProperty -Name $nic.Name -ErrorAction SilentlyContinue
                foreach ($ap in $advProps) {
                    if ($targetKeywords -contains $ap.RegistryKeyword) {
                        [void]$capturedProps.Add(@{
                            adapter = $nic.Name
                            keyword = $ap.RegistryKeyword
                            value   = $ap.RegistryValue
                        })
                    }
                }
            }
        }

        Save-CapturedState -Id $stateKey -CapturedItems $capturedProps.ToArray()

        Invoke-Mutation -Description 'Desativar EEE, Green Ethernet e economia de energia no adaptador de rede ativo' -Action {
            if (-not (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue)) {
                return
            }
            $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
            foreach ($nic in $adapters) {
                $advProps = Get-NetAdapterAdvancedProperty -Name $nic.Name -ErrorAction SilentlyContinue
                foreach ($ap in $advProps) {
                    if ($targetKeywords -contains $ap.RegistryKeyword) {
                        Set-NetAdapterAdvancedProperty -Name $nic.Name -RegistryKeyword $ap.RegistryKeyword -RegistryValue 0 -NoRestart -ErrorAction SilentlyContinue
                    }
                }
                if (Get-Command Disable-NetAdapterPowerManagement -ErrorAction SilentlyContinue) {
                    Disable-NetAdapterPowerManagement -Name $nic.Name -NoRestart -ErrorAction SilentlyContinue
                }
            }
        } | Out-Null
    }
    else {
        $cap = Get-CapturedState -Id $stateKey
        Invoke-Mutation -Description 'Restaurar propriedades originais de energia do adaptador de rede' -Action {
            if ($cap -and $cap.captured) {
                foreach ($item in $cap.captured) {
                    if ($item.adapter -and $item.keyword -and $null -ne $item.value) {
                        Set-NetAdapterAdvancedProperty -Name $item.adapter -RegistryKeyword $item.keyword -RegistryValue $item.value -NoRestart -ErrorAction SilentlyContinue
                    }
                }
            }
            if (Get-Command Enable-NetAdapterPowerManagement -ErrorAction SilentlyContinue) {
                $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
                foreach ($nic in $adapters) {
                    Enable-NetAdapterPowerManagement -Name $nic.Name -NoRestart -ErrorAction SilentlyContinue
                }
            }
        } | Out-Null
        Remove-CapturedState -Id $stateKey
    }
}

function Disable-RiotClientStartup {
    [CmdletBinding()]
    param(
        [ValidateSet('Apply', 'Undo')]
        [string]$Mode = 'Apply'
    )

    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $approvedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
    $stateKey = 'Val_RiotClient_Cleanup'

    $entryNames = New-Object 'System.Collections.Generic.List[string]'
    if (Test-Path -LiteralPath $runKey) {
        $runItem = Get-Item -LiteralPath $runKey -ErrorAction SilentlyContinue
        if ($runItem) {
            foreach ($vn in $runItem.GetValueNames()) {
                $val = [string]$runItem.GetValue($vn, '')
                if ($vn -match '(?i)RiotClient' -or $val -match '(?i)RiotClientServices\.exe') {
                    [void]$entryNames.Add($vn)
                }
            }
        }
    }
    if ($entryNames.Count -eq 0) {
        [void]$entryNames.Add('RiotClient')
    }

    if ($Mode -eq 'Apply') {
        $capList = New-Object 'System.Collections.Generic.List[hashtable]'
        foreach ($en in $entryNames) {
            $curState = Get-RegistryEntryState -Path $approvedKey -Name $en -FallbackType 'Binary'
            [void]$capList.Add(@{
                kind    = 'startupApproved'
                name    = $en
                existed = $curState.ValueExisted
                value   = if ($curState.Value) { [Convert]::ToBase64String([byte[]]$curState.Value) } else { $null }
            })
        }
        Save-CapturedState -Id $stateKey -CapturedItems $capList.ToArray()

        $disabledBytes = [byte[]](0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
        Invoke-Mutation -Description 'Desativar inicialização automática do Riot Client via StartupApproved (mantendo Vanguard intacto)' -Action {
            if (-not (Test-Path -LiteralPath $approvedKey)) {
                New-Item -Path $approvedKey -Force | Out-Null
            }
            foreach ($en in $entryNames) {
                Set-ItemProperty -LiteralPath $approvedKey -Name $en -Value $disabledBytes -Type Binary -Force -ErrorAction Stop
            }
        } | Out-Null
    }
    else {
        $cap = Get-CapturedState -Id $stateKey
        $enabledBytes = [byte[]](0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
        Invoke-Mutation -Description 'Reativar inicialização automática do Riot Client no StartupApproved' -Action {
            if ($cap -and $cap.captured) {
                foreach ($item in $cap.captured) {
                    if ($item.existed -and $item.value) {
                        $origBytes = [Convert]::FromBase64String([string]$item.value)
                        Set-ItemProperty -LiteralPath $approvedKey -Name $item.name -Value $origBytes -Type Binary -Force -ErrorAction SilentlyContinue
                    }
                    elseif (Test-Path -LiteralPath $approvedKey) {
                        Set-ItemProperty -LiteralPath $approvedKey -Name $item.name -Value $enabledBytes -Type Binary -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        } | Out-Null
        Remove-CapturedState -Id $stateKey
    }
}

function Clear-ShaderCache {
    [CmdletBinding()]
    param(
        [string[]]$TargetDirectories
    )

    if (-not $TargetDirectories -or $TargetDirectories.Count -eq 0) {
        $TargetDirectories = @(
            (Join-Path $env:LOCALAPPDATA 'D3DSCache'),
            (Join-Path $env:LOCALAPPDATA 'NVIDIA\DXCache'),
            (Join-Path $env:LOCALAPPDATA 'NVIDIA\GLCache'),
            (Join-Path $env:LOCALAPPDATA 'AMD\DxCache'),
            (Join-Path $env:LOCALAPPDATA 'AMD\DxcCache')
        )
    }

    Invoke-Mutation -Description 'Limpar diretórios de Cache de Shaders (DirectX, NVIDIA e AMD)' -Action {
        $freedBytes = [int64]0
        $deletedCount = 0

        foreach ($dir in $TargetDirectories) {
            if (-not (Test-Path -LiteralPath $dir)) {
                continue
            }
            $files = Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                $len = $f.Length
                try {
                    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                    $freedBytes += $len
                    $deletedCount++
                }
                catch {
                    Write-Verbose ("Arquivo de cache em uso (ignorado): {0}" -f $f.FullName)
                }
            }
        }

        $freedMb = [math]::Round(($freedBytes / 1MB), 2)
        Write-OptimizerLog -Level OK -Message ("Cache de Shaders limpo: {0} arquivos removidos ({1} MB liberados)." -f $deletedCount, $freedMb)
    } | Out-Null
}

function Invoke-GameOptimization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$ProfileConfig,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Optimization,

        [ValidateSet('Apply', 'Undo')]
        [string]$Mode = 'Apply',

        [string]$CustomExePath
    )

    $action = $Optimization.action
    if ($script:AllowedGameActions -notcontains $action) {
        $msg = "Action '$action' na otimização '$($Optimization.id)' não consta na whitelist do game-engine."
        Write-OptimizerLog -Level ERROR -Message $msg
        throw $msg
    }

    switch ($action) {
        'Set-AppCompatFlags' {
            $exe = if ($CustomExePath) { $CustomExePath } else { Find-GameExecutable -ProfileConfig $ProfileConfig }
            if ([string]::IsNullOrWhiteSpace($exe)) {
                Write-OptimizerLog -Level WARN -Message ("Executável de {0} não encontrado para aplicar '{1}'." -f $ProfileConfig.gameName, $Optimization.title)
                return $false
            }
            $flags = if ($Optimization.flags) { $Optimization.flags } else { '~ DISABLEDXMAXIMIZEDWINDOWEDMODE HIGHDPIAWARE' }
            Set-AppCompatFlags -ExecutablePath $exe -Flags $flags -StateKey $Optimization.id -Mode $Mode
            return $true
        }
        'Set-DirectXGpuPreference' {
            $exe = if ($CustomExePath) { $CustomExePath } else { Find-GameExecutable -ProfileConfig $ProfileConfig }
            if ([string]::IsNullOrWhiteSpace($exe)) {
                Write-OptimizerLog -Level WARN -Message ("Executável de {0} não encontrado para aplicar '{1}'." -f $ProfileConfig.gameName, $Optimization.title)
                return $false
            }
            Set-DirectXGpuPreference -ExecutablePath $exe -StateKey $Optimization.id -Mode $Mode
            return $true
        }
        'Optimize-NetworkAdapterGaming' {
            Optimize-NetworkAdapterGaming -Mode $Mode
            return $true
        }
        'Disable-RiotClientStartup' {
            Disable-RiotClientStartup -Mode $Mode
            return $true
        }
        'Clear-ShaderCache' {
            if ($Mode -eq 'Apply') {
                Clear-ShaderCache
            }
            else {
                Write-OptimizerLog -Level INFO -Message 'A limpeza de Cache de Shaders é uma operação de manutenção (o driver recria o cache automaticamente).'
            }
            return $true
        }
        'Optimize-UsbPower' {
            if ($Mode -eq 'Apply') {
                Optimize-UsbPower
            }
            else {
                Restore-UsbPower
            }
            return $true
        }
    }

    return $false
}

function Test-GameOptimizationApplied {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$ProfileConfig,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Optimization,

        [string]$CustomExePath
    )

    switch ($Optimization.action) {
        'Set-AppCompatFlags' {
            $exe = if ($CustomExePath) { $CustomExePath } else { Find-GameExecutable -ProfileConfig $ProfileConfig }
            if ([string]::IsNullOrWhiteSpace($exe)) { return $false }
            $layersKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
            $st = Get-RegistryEntryState -Path $layersKey -Name $exe -FallbackType 'String'
            return ($st.ValueExisted -and ($st.Value -match 'DISABLEDXMAXIMIZEDWINDOWEDMODE'))
        }
        'Set-DirectXGpuPreference' {
            $exe = if ($CustomExePath) { $CustomExePath } else { Find-GameExecutable -ProfileConfig $ProfileConfig }
            if ([string]::IsNullOrWhiteSpace($exe)) { return $false }
            $gpuKey = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
            $st = Get-RegistryEntryState -Path $gpuKey -Name $exe -FallbackType 'String'
            return ($st.ValueExisted -and ($st.Value -match 'GpuPreference=2'))
        }
        'Optimize-NetworkAdapterGaming' {
            return ($null -ne (Get-CapturedState -Id 'NetworkAdapterGaming'))
        }
        'Disable-RiotClientStartup' {
            $approvedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
            $st = Get-RegistryEntryState -Path $approvedKey -Name 'RiotClient' -FallbackType 'Binary'
            if ($st.ValueExisted -and $st.Value -is [byte[]] -and $st.Value.Length -ge 1) {
                return ($st.Value[0] -eq 0x03)
            }
            return ($null -ne (Get-CapturedState -Id 'Val_RiotClient_Cleanup'))
        }
        'Optimize-UsbPower' {
            return (Test-UsbPowerOptimized)
        }
        default {
            return $false
        }
    }
}
