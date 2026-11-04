# Detecção de Hardware (CPU/GPU/Chassi/SSD/Build) e Otimizações de Energia e Portas USB

#region dev-only
if (-not (Get-Command Write-OptimizerLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\core\logger.ps1')
}
if (-not (Get-Command Save-CapturedState -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\core\backup.ps1')
}
#endregion

function Get-OptiKitHardware {
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    if ($script:OptiKitHardwareCache -and -not $Force) {
        return $script:OptiKitHardwareCache
    }

    $cpuName = 'CPU Desconhecida'
    try {
        $regCpu = Get-ItemProperty -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -Name 'ProcessorNameString' -ErrorAction SilentlyContinue
        if ($regCpu -and $regCpu.ProcessorNameString) {
            $cpuName = $regCpu.ProcessorNameString.Trim()
        }
    }
    catch {
        Write-Verbose ("Falha ao ler nome da CPU do registro: {0}" -f $_.Exception.Message)
    }

    $isX3D = [bool]($cpuName -match '(?i)\b\d{4}X3D\b')

    $cpuCores = 0
    try {
        $cpuCim = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue
        if ($cpuCim) {
            $cpuCores = [int](($cpuCim | Measure-Object -Property NumberOfCores -Sum).Sum)
        }
    }
    catch {
        Write-Verbose ("Falha ao obter número de núcleos da CPU: {0}" -f $_.Exception.Message)
    }

    # X3D dual-CCD: 7900X3D/7950X3D/9900X3D/9950X3D (12/16 núcleos). Single-CCD X3D tem até 8.
    $isX3DDualCcd = $isX3D -and (($cpuName -match '(?i)\b(79|99)\d{2}X3D\b') -or ($cpuCores -gt 8))

    $isLaptop = $false
    try {
        $enclosure = Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction SilentlyContinue
        $laptopChassis = @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32)
        if ($enclosure -and $enclosure.ChassisTypes) {
            foreach ($ct in $enclosure.ChassisTypes) {
                if ($laptopChassis -contains [int]$ct) {
                    $isLaptop = $true
                    break
                }
            }
        }
        if (-not $isLaptop) {
            $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
            if ($battery) {
                $isLaptop = $true
            }
        }
    }
    catch {
        Write-Verbose ("Falha ao detectar chassi/bateria via CIM: {0}" -f $_.Exception.Message)
    }

    $gpuNames = New-Object 'System.Collections.Generic.List[string]'
    $gpuVendors = New-Object 'System.Collections.Generic.List[string]'
    try {
        $gpus = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue
        foreach ($g in $gpus) {
            if ($g.Name) {
                [void]$gpuNames.Add($g.Name.Trim())
                if ($g.Name -match '(?i)NVIDIA|GeForce|RTX|GTX') {
                    if (-not $gpuVendors.Contains('NVIDIA')) { [void]$gpuVendors.Add('NVIDIA') }
                }
                elseif ($g.Name -match '(?i)AMD|Radeon|RX\s') {
                    if (-not $gpuVendors.Contains('AMD')) { [void]$gpuVendors.Add('AMD') }
                }
                elseif ($g.Name -match '(?i)Intel|Arc|Iris|UHD') {
                    if (-not $gpuVendors.Contains('Intel')) { [void]$gpuVendors.Add('Intel') }
                }
            }
        }
    }
    catch {
        Write-Verbose ("Falha ao detectar GPUs via CIM: {0}" -f $_.Exception.Message)
    }

    $isSsd = $true
    try {
        if (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue) {
            $disks = Get-PhysicalDisk -ErrorAction SilentlyContinue
            if ($disks) {
                $hddOnly = ($disks | Where-Object { $_.MediaType -eq 'SSD' }).Count -eq 0 -and ($disks | Where-Object { $_.MediaType -eq 'HDD' }).Count -gt 0
                if ($hddOnly) { $isSsd = $false }
            }
        }
    }
    catch {
        Write-Verbose ("Falha ao detectar tipo de disco: {0}" -f $_.Exception.Message)
    }

    $osBuild = [int][Environment]::OSVersion.Version.Build
    $isWin11 = ($osBuild -ge 22000)
    $osLabel = if ($isWin11) { "Windows 11 (Build $osBuild)" } else { "Windows 10 (Build $osBuild)" }
    $chassisLabel = if ($isLaptop) { 'Notebook' } else { 'Desktop' }
    $gpuPrimary = if ($gpuNames.Count -gt 0) { $gpuNames[0] } else { 'GPU Padrão' }

    $script:OptiKitHardwareCache = [pscustomobject]@{
        CpuName         = $cpuName
        CpuCores        = $cpuCores
        IsX3D           = $isX3D
        IsX3DDualCcd    = $isX3DDualCcd
        IsLaptop        = $isLaptop
        GpuNames        = $gpuNames.ToArray()
        GpuVendors      = $gpuVendors.ToArray()
        SystemDiskIsSSD = $isSsd
        OsBuild         = $osBuild
        IsWin11         = $isWin11
        Summary         = "$cpuName | $gpuPrimary | $chassisLabel | $osLabel"
    }

    return $script:OptiKitHardwareCache
}

function Test-OptiKitTweakBlocked {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Tweak,

        [pscustomobject]$Hardware
    )

    $guards = @($Tweak.blockedOn)
    if ($guards.Count -eq 0) {
        return $null
    }

    if (-not $Hardware) {
        $Hardware = Get-OptiKitHardware
    }

    foreach ($guard in $guards) {
        $isBlocked = switch ([string]$guard) {
            'X3DDualCcd' { [bool]$Hardware.IsX3DDualCcd }
            'X3D'        { [bool]$Hardware.IsX3D }
            'Laptop'     { [bool]$Hardware.IsLaptop }
            default      { $false }
        }

        if ($isBlocked) {
            if (-not [string]::IsNullOrWhiteSpace($Tweak.blockedMessage)) {
                return [string]$Tweak.blockedMessage
            }
            return ("Bloqueado neste hardware ({0})." -f $guard)
        }
    }

    return $null
}

function Get-ActivePowerPlanGuid {
    [CmdletBinding()]
    param()

    try {
        $out = & powercfg.exe /getactivescheme 2>$null | Out-String
        if ($out -match '([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') {
            return $Matches[1].ToLowerInvariant()
        }
    }
    catch {
        Write-Verbose ("Erro ao obter plano de energia ativo: {0}" -f $_.Exception.Message)
    }
    return '381b4222-f694-41f0-9685-ff5bb260df2e'
}

function Set-OptiKitSmartPowerPlan {
    [CmdletBinding()]
    param()

    $hw = Get-OptiKitHardware
    $currentGuid = Get-ActivePowerPlanGuid
    Save-CapturedState -Id 'PowerPlanOriginal' -CapturedItems @(
        @{ kind = 'powerplan'; guid = $currentGuid }
    )

    $balancedGuid = '381b4222-f694-41f0-9685-ff5bb260df2e'
    $highPerfGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'

    if ($hw.IsLaptop) {
        Write-OptimizerLog -Level INFO -Message 'Notebook detectado: mantendo plano Equilibrado (Balanced) para preservar autonomia e gerenciamento térmico.'
        Invoke-Mutation -Description 'Ativar plano Equilibrado (Balanced) para Notebook' -Action {
            & powercfg.exe /setactive $balancedGuid | Out-Null
        } | Out-Null
        return
    }

    if ($hw.IsX3D) {
        Write-OptimizerLog -Level INFO -Message ("CPU AMD Ryzen X3D detectada ({0}): recomendando e ativando plano Equilibrado (exigido pelo Core Parking do 3D V-Cache)." -f $hw.CpuName)
        Invoke-Mutation -Description 'Ativar plano Equilibrado para AMD Ryzen X3D (sem suspensão automática em Desktop)' -Action {
            & powercfg.exe /setactive $balancedGuid | Out-Null
            & powercfg.exe /change standby-timeout-ac 0 | Out-Null
        } | Out-Null
        return
    }

    Invoke-Mutation -Description 'Ativar plano de energia Alto Desempenho (Desktop) e desativar suspensão automática' -Action {
        if (-not (Test-OptiKitUltimatePowerPlan)) {
            & powercfg.exe /setactive $highPerfGuid | Out-Null
        }
        & powercfg.exe /change standby-timeout-ac 0 | Out-Null
    } | Out-Null
}

function Enable-OptiKitUltimatePowerPlan {
    [CmdletBinding()]
    param()

    $currentGuid = Get-ActivePowerPlanGuid
    Save-CapturedState -Id 'PowerPlanOriginal' -CapturedItems @(
        @{ kind = 'powerplan'; guid = $currentGuid }
    )

    $ultimateTemplate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    Invoke-Mutation -Description 'Desbloquear e ativar plano Ultimate Performance (sem duplicar)' -Action {
        $listOut = & powercfg.exe /list 2>$null | Out-String
        $targetGuid = $null

        foreach ($line in ($listOut -split "\r?\n")) {
            if ($line -match '(?i)(e9a42b02-d5df-448d-aa00-03f14749eb61|Ultimate Performance|Desempenho M.ximo)' -and
                $line -match '([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') {
                $targetGuid = $Matches[1].ToLowerInvariant()
                break
            }
        }

        if (-not $targetGuid) {
            $dupOut = & powercfg.exe -duplicatescheme $ultimateTemplate 2>$null | Out-String
            if ($dupOut -match '([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') {
                $targetGuid = $Matches[1].ToLowerInvariant()
            }
            else {
                $targetGuid = $ultimateTemplate
            }
        }

        & powercfg.exe /setactive $targetGuid | Out-Null
        & powercfg.exe /change standby-timeout-ac 0 | Out-Null
    } | Out-Null
}

function Restore-OptiKitPowerPlan {
    [CmdletBinding()]
    param()

    $captured = Get-CapturedState -Id 'PowerPlanOriginal'
    $targetGuid = '381b4222-f694-41f0-9685-ff5bb260df2e'
    if ($captured -and $captured.captured -and $captured.captured.Count -gt 0 -and $captured.captured[0].guid) {
        $targetGuid = $captured.captured[0].guid
    }

    Invoke-Mutation -Description ("Restaurar plano de energia anterior ({0})" -f $targetGuid) -Action {
        & powercfg.exe /setactive $targetGuid | Out-Null
    } | Out-Null

    Remove-CapturedState -Id 'PowerPlanOriginal'
}

function Test-OptiKitSmartPowerPlan {
    [CmdletBinding()]
    param()

    $hw = Get-OptiKitHardware
    $active = Get-ActivePowerPlanGuid
    if ($hw.IsLaptop -or $hw.IsX3D) {
        return ($active -eq '381b4222-f694-41f0-9685-ff5bb260df2e')
    }
    return (($active -eq '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c') -or (Test-OptiKitUltimatePowerPlan))
}

function Test-OptiKitUltimatePowerPlan {
    [CmdletBinding()]
    param()

    try {
        $out = & powercfg.exe /getactivescheme 2>$null | Out-String
        return [bool]($out -match '(?i)(e9a42b02-d5df-448d-aa00-03f14749eb61|Ultimate Performance|Desempenho M.ximo)')
    }
    catch {
        return $false
    }
}

function Disable-OptiKitHibernation {
    [CmdletBinding()]
    param()

    Invoke-Mutation -Description 'Desativar hibernação via powercfg /hibernate off' -Action {
        & powercfg.exe /hibernate off | Out-Null
    } | Out-Null
}

function Enable-OptiKitHibernation {
    [CmdletBinding()]
    param()

    Invoke-Mutation -Description 'Reativar hibernação via powercfg /hibernate on' -Action {
        & powercfg.exe /hibernate on | Out-Null
    } | Out-Null
}

function Optimize-UsbPower {
    [CmdletBinding()]
    param()

    $usbSubGroup = '2a737441-1930-4402-8d77-b2bebba308a3'
    $usbSelectiveSuspend = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
    $usbSettingsKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\USB'

    $existed = $false
    $prevVal = $null
    if (Test-Path -LiteralPath $usbSettingsKey) {
        $prop = Get-ItemProperty -LiteralPath $usbSettingsKey -Name 'DisableSelectiveSuspend' -ErrorAction SilentlyContinue
        if ($null -ne $prop -and ($prop.PSObject.Properties.Name -contains 'DisableSelectiveSuspend')) {
            $existed = $true
            $prevVal = $prop.DisableSelectiveSuspend
        }
    }

    Save-CapturedState -Id 'UsbPowerOptimization' -CapturedItems @(
        @{ kind = 'registry'; path = $usbSettingsKey; name = 'DisableSelectiveSuspend'; existed = $existed; type = 'DWord'; value = $prevVal }
    )

    Invoke-Mutation -Description 'Desativar Suspensão Seletiva de USB no plano de energia ativo e no controlador USB' -Action {
        & powercfg.exe /setacvalueindex SCHEME_CURRENT $usbSubGroup $usbSelectiveSuspend 0 | Out-Null
        & powercfg.exe /setactive SCHEME_CURRENT | Out-Null

        if (-not (Test-Path -LiteralPath $usbSettingsKey)) {
            New-Item -Path $usbSettingsKey -Force | Out-Null
        }
        Set-ItemProperty -LiteralPath $usbSettingsKey -Name 'DisableSelectiveSuspend' -Value 1 -Type DWord -ErrorAction Stop

        $hubs = Get-CimInstance -Namespace 'root\wmi' -ClassName 'MSPower_DeviceEnable' -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceName -match '(?i)^USB\\(ROOT_HUB|VID_)' }
        foreach ($hub in $hubs) {
            if ($hub.Enable -eq $true) {
                $hub.Enable = $false
                Set-CimInstance -InputObject $hub -ErrorAction SilentlyContinue | Out-Null
            }
        }
    } | Out-Null
}

function Restore-UsbPower {
    [CmdletBinding()]
    param()

    $usbSubGroup = '2a737441-1930-4402-8d77-b2bebba308a3'
    $usbSelectiveSuspend = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
    $usbSettingsKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\USB'
    $captured = Get-CapturedState -Id 'UsbPowerOptimization'

    Invoke-Mutation -Description 'Restaurar configurações padrão de Suspensão Seletiva de USB' -Action {
        & powercfg.exe /setacvalueindex SCHEME_CURRENT $usbSubGroup $usbSelectiveSuspend 1 | Out-Null
        & powercfg.exe /setactive SCHEME_CURRENT | Out-Null

        if ($captured -and $captured.captured -and $captured.captured.Count -gt 0 -and $captured.captured[0].existed) {
            Set-ItemProperty -LiteralPath $usbSettingsKey -Name 'DisableSelectiveSuspend' -Value $captured.captured[0].value -Type DWord -ErrorAction SilentlyContinue
        }
        elseif (Test-Path -LiteralPath $usbSettingsKey) {
            Remove-ItemProperty -LiteralPath $usbSettingsKey -Name 'DisableSelectiveSuspend' -ErrorAction SilentlyContinue
        }
    } | Out-Null

    Remove-CapturedState -Id 'UsbPowerOptimization'
}

function Test-UsbPowerOptimized {
    [CmdletBinding()]
    param()

    $usbSettingsKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\USB'
    if (-not (Test-Path -LiteralPath $usbSettingsKey)) {
        return $false
    }
    $prop = Get-ItemProperty -LiteralPath $usbSettingsKey -Name 'DisableSelectiveSuspend' -ErrorAction SilentlyContinue
    return ($null -ne $prop -and $prop.DisableSelectiveSuspend -eq 1)
}
