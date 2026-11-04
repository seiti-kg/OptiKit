# Verificador de Estado Atual (State Checker): inspeciona Registro, Serviços, Tarefas, Appx e CheckScripts

#region dev-only
if (-not (Get-Command Get-RegistryEntryState -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\modules\tweak-engine.ps1')
}
if (-not (Get-Command Test-GameOptimizationApplied -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\modules\game-engine.ps1')
}
#endregion

$script:AllowedCheckScripts = @(
    'Test-OptiKitSmartPowerPlan',
    'Test-OptiKitUltimatePowerPlan',
    'Test-UsbPowerOptimized',
    'Test-OptiKitOneDriveRemoved'
)

function Test-TweakApplied {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Tweak
    )

    if (-not [string]::IsNullOrWhiteSpace($Tweak.checkScript)) {
        $fn = $Tweak.checkScript
        if ($script:AllowedCheckScripts -contains $fn) {
            try {
                $ok = [bool](& $fn)
                return $(if ($ok) { 'Applied' } else { 'NotApplied' })
            }
            catch {
                return 'Unknown'
            }
        }
        return 'Unknown'
    }

    $totalChecks = 0
    $matchedChecks = 0

    foreach ($reg in @($Tweak.registry)) {
        $totalChecks++
        $st = Get-RegistryEntryState -Path $reg.path -Name $reg.name -FallbackType $reg.type
        if ($reg.value -is [string] -and $reg.value -eq '<RemoveKey>') {
            if (-not $st.KeyExisted) { $matchedChecks++ }
        }
        elseif ($reg.value -is [string] -and $reg.value -eq '<RemoveEntry>') {
            if (-not $st.ValueExisted) { $matchedChecks++ }
        }
        else {
            if ($st.ValueExisted -and ([string]$st.Value -eq [string]$reg.value)) {
                $matchedChecks++
            }
        }
    }

    foreach ($svc in @($Tweak.services)) {
        $svcObj = Get-Service -Name $svc.name -ErrorAction SilentlyContinue
        if ($null -ne $svcObj) {
            $totalChecks++
            if ($svcObj.StartType.ToString() -eq $svc.startupType) {
                $matchedChecks++
            }
        }
    }

    foreach ($tsk in @($Tweak.scheduledTasks)) {
        $tskObj = Get-ScheduledTask -TaskPath $tsk.path -TaskName $tsk.name -ErrorAction SilentlyContinue
        if ($null -ne $tskObj) {
            $totalChecks++
            if ($tskObj.State.ToString() -eq $tsk.state) {
                $matchedChecks++
            }
        }
    }

    foreach ($apx in @($Tweak.appx)) {
        $totalChecks++
        $pkg = Get-AppxPackage -Name "*$($apx.name)*" -ErrorAction SilentlyContinue
        if ($null -eq $pkg) {
            $matchedChecks++
        }
    }

    if ($totalChecks -eq 0) {
        return 'Unknown'
    }
    if ($matchedChecks -eq $totalChecks) {
        return 'Applied'
    }
    if ($matchedChecks -eq 0) {
        return 'NotApplied'
    }
    return 'Partial'
}

function Get-AllTweaksState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$TweaksConfig,

        [pscustomobject]$GameProfilesConfig
    )

    $tweakStates = @{}
    foreach ($prop in $TweaksConfig.PSObject.Properties) {
        $tweakStates[$prop.Name] = Test-TweakApplied -Id $prop.Name -Tweak $prop.Value
    }

    $gameStates = @{}
    if ($GameProfilesConfig) {
        foreach ($gProp in $GameProfilesConfig.PSObject.Properties) {
            $prof = $gProp.Value
            foreach ($opt in @($prof.optimizations)) {
                $gameStates[$opt.id] = [bool](Test-GameOptimizationApplied -ProfileConfig $prof -Optimization $opt)
            }
        }
    }

    return [pscustomobject]@{
        Tweaks        = $tweakStates
        GameOpts      = $gameStates
        CapturedState = Read-OptiKitStateFile
    }
}
