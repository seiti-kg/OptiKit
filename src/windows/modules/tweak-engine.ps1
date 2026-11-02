# Motor de execução e reversão (Apply / Undo) de Tweaks: Registro, Serviços, Tarefas Agendadas, Appx e Helpers

#region dev-only
if (-not (Get-Command Write-OptimizerLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\core\logger.ps1')
}
if (-not (Get-Command Save-CapturedState -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\core\backup.ps1')
}
if (-not (Get-Command Get-RedimoHardware -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'hardware-utils.ps1')
}
if (-not (Get-Command Install-RedimoApp -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'winget-engine.ps1')
}
#endregion

$script:ProtectedAppxPackages = @(
    'Microsoft.WindowsStore',
    'Microsoft.StorePurchaseApp',
    'Microsoft.WindowsCalculator',
    'Microsoft.ScreenSketch',
    'Microsoft.XboxIdentityProvider',
    'Microsoft.GamingServices',
    'Microsoft.DesktopAppInstaller',
    'Microsoft.VCLibs.140.00',
    'Microsoft.UI.Xaml.2.7',
    'Microsoft.UI.Xaml.2.8'
)

$script:AllowedTweakScripts = @(
    'Set-RedimoSmartPowerPlan',
    'Enable-RedimoUltimatePowerPlan',
    'Restore-RedimoPowerPlan',
    'Disable-RedimoHibernation',
    'Enable-RedimoHibernation',
    'Optimize-UsbPower',
    'Restore-UsbPower',
    'Remove-RedimoOneDrive',
    'Install-RedimoOneDrive'
)

function Test-AntiCheatGuardrail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Tweak
    )

    foreach ($svc in @($Tweak.services)) {
        if ($svc.name -match '^(?i)(vgc|vgk|BEService|EasyAntiCheat|FACEITService)$') {
            $msg = "GUARDRAIL ANTI-CHEAT: O tweak '$Id' tentou modificar o serviço protegido de anti-cheat '$($svc.name)'. Operação abortada."
            Write-OptimizerLog -Level ERROR -Message $msg
            throw $msg
        }
    }

    foreach ($reg in @($Tweak.registry)) {
        if ($reg.name -match '^(?i)EnableVirtualizationBasedSecurity$' -or
            $reg.path -match '(?i)\\Services\\(vgc|vgk|TPM)\b' -or
            $reg.path -match '(?i)\\SecureBoot\\State\b') {
            $msg = "GUARDRAIL ANTI-CHEAT: O tweak '$Id' tentou modificar chave crítica de segurança/anti-cheat ('$($reg.path)\$($reg.name)'). Operação abortada."
            Write-OptimizerLog -Level ERROR -Message $msg
            throw $msg
        }
    }

    foreach ($apx in @($Tweak.appx)) {
        if ($script:ProtectedAppxPackages -contains $apx.name) {
            $msg = "GUARDRAIL DE SISTEMA: O tweak '$Id' tentou remover o pacote essencial protegido '$($apx.name)'. Operação abortada."
            Write-OptimizerLog -Level ERROR -Message $msg
            throw $msg
        }
    }
}

function Get-RegistryEntryState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$FallbackType = 'DWord'
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            KeyExisted   = $false
            ValueExisted = $false
            Value        = $null
            Type         = $FallbackType
        }
    }

    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        $lookupName = if ($Name -eq '(Default)') { '' } else { $Name }
        $valNames = @($item.GetValueNames())
        $valExisted = ($valNames -contains $lookupName)

        if (-not $valExisted) {
            return [pscustomobject]@{
                KeyExisted   = $true
                ValueExisted = $false
                Value        = $null
                Type         = $FallbackType
            }
        }

        $rawVal = $item.GetValue($lookupName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $kind = $FallbackType
        try {
            $kind = $item.GetValueKind($lookupName).ToString()
        }
        catch {
            $kind = $FallbackType
        }

        return [pscustomobject]@{
            KeyExisted   = $true
            ValueExisted = $true
            Value        = $rawVal
            Type         = $kind
        }
    }
    catch {
        return [pscustomobject]@{
            KeyExisted   = $false
            ValueExisted = $false
            Value        = $null
            Type         = $FallbackType
        }
    }
}

function Set-RegistryEntryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$Type = 'DWord',

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        $Value
    )

    if ($Value -is [string] -and $Value -eq '<RemoveKey>') {
        Invoke-Mutation -Description ("Remover chave de registro '{0}'" -f $Path) -Action {
            if (Test-Path -LiteralPath $Path) {
                Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            }
        } | Out-Null
        return
    }

    if ($Value -is [string] -and $Value -eq '<RemoveEntry>') {
        Invoke-Mutation -Description ("Remover valor de registro '{0}\{1}'" -f $Path, $Name) -Action {
            if (Test-Path -LiteralPath $Path) {
                if ($Name -eq '(Default)') {
                    $regItem = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
                    if ($regItem -and (@($regItem.GetValueNames()) -contains '')) {
                        Remove-ItemProperty -LiteralPath $Path -Name '(Default)' -Force -ErrorAction SilentlyContinue
                    }
                }
                else {
                    $prop = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
                    if ($null -ne $prop) {
                        Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop
                    }
                }
            }
        } | Out-Null
        return
    }

    Invoke-Mutation -Description ("Definir registro '{0}\{1}' = '{2}' ({3})" -f $Path, $Name, $Value, $Type) -Action {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }

        if ($Name -eq '(Default)') {
            Set-Item -LiteralPath $Path -Value ([string]$Value) -ErrorAction Stop
        }
        else {
            $castValue = switch ($Type) {
                'DWord'  { [int]$Value }
                'QWord'  { [long]$Value }
                'String' { [string]$Value }
                'ExpandString' { [string]$Value }
                default  { $Value }
            }
            Set-ItemProperty -LiteralPath $Path -Name $Name -Value $castValue -Type $Type -Force -ErrorAction Stop
        }
    } | Out-Null
}

function Set-ServiceStartupState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,

        [Parameter(Mandatory = $true)]
        [string]$StartupType
    )

    Invoke-Mutation -Description ("Configurar serviço '{0}' para '{1}'" -f $ServiceName, $StartupType) -Action {
        $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-OptimizerLog -Level INFO -Message ("Serviço '{0}' não está presente nesta edição do Windows (ignorado)." -f $ServiceName)
            return
        }

        if ($StartupType -eq 'AutomaticDelayedStart') {
            Start-Process -FilePath 'sc.exe' -ArgumentList @('config', $ServiceName, 'start=', 'delayed-auto') -NoNewWindow -Wait | Out-Null
        }
        else {
            Set-Service -Name $ServiceName -StartupType $StartupType -ErrorAction Stop
        }

        if ($StartupType -eq 'Disabled' -and $svc.Status -eq 'Running') {
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        }
    } | Out-Null
}

function Set-ScheduledTaskState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskPath,

        [Parameter(Mandatory = $true)]
        [string]$TaskName,

        [Parameter(Mandatory = $true)]
        [string]$DesiredState
    )

    Invoke-Mutation -Description ("Configurar tarefa agendada '{0}{1}' para '{2}'" -f $TaskPath, $TaskName, $DesiredState) -Action {
        $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-OptimizerLog -Level INFO -Message ("Tarefa agendada '{0}{1}' não existe neste sistema (ignorada)." -f $TaskPath, $TaskName)
            return
        }

        if ($DesiredState -eq 'Disabled') {
            Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
        }
        else {
            Enable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
        }
    } | Out-Null
}

function Invoke-AppxRemoval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,

        [Parameter(Mandatory = $true)]
        [string]$StoreId,

        [ValidateSet('Apply', 'Undo')]
        [string]$Mode = 'Apply'
    )

    if ($script:ProtectedAppxPackages -contains $PackageName) {
        throw "Pacote Appx '$PackageName' é protegido e não pode ser removido."
    }

    if ($Mode -eq 'Apply') {
        Invoke-Mutation -Description ("Remover pacote Appx '{0}' (usuários + provisionamento)" -f $PackageName) -Action {
            $pkgs = Get-AppxPackage -AllUsers -Name "*$PackageName*" -ErrorAction SilentlyContinue
            foreach ($p in $pkgs) {
                Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction SilentlyContinue
            }
            $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like "*$PackageName*" }
            foreach ($pr in $prov) {
                Remove-AppxProvisionedPackage -Online -PackageName $pr.PackageName -ErrorAction SilentlyContinue | Out-Null
            }
        } | Out-Null
    }
    else {
        Invoke-Mutation -Description ("Reinstalar pacote Appx '{0}' (Store ID: {1}) via Winget" -f $PackageName, $StoreId) -Action {
            $wg = Test-WingetAvailable
            if ($wg.Available) {
                $argsList = @('install', '--id', $StoreId, '--source', 'msstore', '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements')
                Start-Process -FilePath $wg.Path -ArgumentList $argsList -NoNewWindow -Wait | Out-Null
            }
            else {
                Write-OptimizerLog -Level WARN -Message ("Winget indisponível para reinstalar '{0}' ({1})." -f $PackageName, $StoreId)
            }
        } | Out-Null
    }
}

function Invoke-TweakHelperScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FunctionName
    )

    if ($script:AllowedTweakScripts -notcontains $FunctionName) {
        $msg = "Função helper '$FunctionName' não consta na whitelist de segurança do tweak-engine."
        Write-OptimizerLog -Level ERROR -Message $msg
        throw $msg
    }

    & $FunctionName
}

function Invoke-Tweak {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Tweak,

        [ValidateSet('Apply', 'Undo')]
        [string]$Mode = 'Apply'
    )

    Test-AntiCheatGuardrail -Id $Id -Tweak $Tweak

    if ($Mode -eq 'Apply') {
        Write-OptimizerLog -Level INFO -Message ("Aplicando tweak: {0} ({1})" -f $Tweak.title, $Id)

        $capturedItems = New-Object 'System.Collections.Generic.List[hashtable]'
        $regPathsToBackup = New-Object 'System.Collections.Generic.List[string]'

        foreach ($reg in @($Tweak.registry)) {
            $state = Get-RegistryEntryState -Path $reg.path -Name $reg.name -FallbackType $reg.type
            [void]$capturedItems.Add(@{
                kind            = 'registry'
                path            = $reg.path
                name            = $reg.name
                keyExisted      = [bool]$state.KeyExisted
                existed         = [bool]$state.ValueExisted
                type            = $state.Type
                value           = $state.Value
                isRemoveKeyHint = ($reg.originalValue -eq '<RemoveKey>')
            })
            if ($state.KeyExisted) {
                [void]$regPathsToBackup.Add($reg.path)
            }
        }

        foreach ($svc in @($Tweak.services)) {
            $svcObj = Get-Service -Name $svc.name -ErrorAction SilentlyContinue
            [void]$capturedItems.Add(@{
                kind        = 'service'
                name        = $svc.name
                existed     = ($null -ne $svcObj)
                startupType = if ($svcObj) { $svcObj.StartType.ToString() } else { $svc.originalType }
            })
        }

        foreach ($tsk in @($Tweak.scheduledTasks)) {
            $tskObj = Get-ScheduledTask -TaskPath $tsk.path -TaskName $tsk.name -ErrorAction SilentlyContinue
            [void]$capturedItems.Add(@{
                kind    = 'scheduledTask'
                path    = $tsk.path
                name    = $tsk.name
                existed = ($null -ne $tskObj)
                state   = if ($tskObj) { $tskObj.State.ToString() } else { $tsk.originalState }
            })
        }

        foreach ($apx in @($Tweak.appx)) {
            $pkgObj = Get-AppxPackage -Name "*$($apx.name)*" -ErrorAction SilentlyContinue
            [void]$capturedItems.Add(@{
                kind    = 'appx'
                name    = $apx.name
                storeId = $apx.storeId
                existed = ($null -ne $pkgObj)
            })
        }

        Save-CapturedState -Id $Id -CapturedItems $capturedItems.ToArray()
        if ($regPathsToBackup.Count -gt 0) {
            Export-RegistryKeyBackup -Paths $regPathsToBackup.ToArray() | Out-Null
        }

        foreach ($reg in @($Tweak.registry)) {
            Set-RegistryEntryValue -Path $reg.path -Name $reg.name -Type $reg.type -Value $reg.value
        }

        foreach ($svc in @($Tweak.services)) {
            Set-ServiceStartupState -ServiceName $svc.name -StartupType $svc.startupType
        }

        foreach ($tsk in @($Tweak.scheduledTasks)) {
            Set-ScheduledTaskState -TaskPath $tsk.path -TaskName $tsk.name -DesiredState $tsk.state
        }

        foreach ($apx in @($Tweak.appx)) {
            Invoke-AppxRemoval -PackageName $apx.name -StoreId $apx.storeId -Mode 'Apply'
        }

        foreach ($fn in @($Tweak.invokeScript)) {
            if (-not [string]::IsNullOrWhiteSpace($fn)) {
                Invoke-TweakHelperScript -FunctionName $fn
            }
        }

        return $true
    }
    else {
        Write-OptimizerLog -Level INFO -Message ("Revertendo tweak (Undo): {0} ({1})" -f $Tweak.title, $Id)
        $capturedRecord = Get-CapturedState -Id $Id
        $capturedList = if ($capturedRecord -and $capturedRecord.captured) { @($capturedRecord.captured) } else { @() }

        foreach ($fn in @($Tweak.undoScript)) {
            if (-not [string]::IsNullOrWhiteSpace($fn)) {
                Invoke-TweakHelperScript -FunctionName $fn
            }
        }

        foreach ($apx in @($Tweak.appx)) {
            Invoke-AppxRemoval -PackageName $apx.name -StoreId $apx.storeId -Mode 'Undo'
        }

        foreach ($tsk in @($Tweak.scheduledTasks)) {
            $capTask = $capturedList | Where-Object { $_.kind -eq 'scheduledTask' -and $_.path -eq $tsk.path -and $_.name -eq $tsk.name } | Select-Object -First 1
            $targetState = if ($capTask -and $capTask.existed -and $capTask.state) { $capTask.state } else { $tsk.originalState }
            Set-ScheduledTaskState -TaskPath $tsk.path -TaskName $tsk.name -DesiredState $targetState
        }

        foreach ($svc in @($Tweak.services)) {
            $capSvc = $capturedList | Where-Object { $_.kind -eq 'service' -and $_.name -eq $svc.name } | Select-Object -First 1
            $targetType = if ($capSvc -and $capSvc.existed -and $capSvc.startupType) { $capSvc.startupType } else { $svc.originalType }
            Set-ServiceStartupState -ServiceName $svc.name -StartupType $targetType
        }

        $regArray = @($Tweak.registry)
        for ($i = $regArray.Count - 1; $i -ge 0; $i--) {
            $reg = $regArray[$i]
            $capReg = $capturedList | Where-Object { $_.kind -eq 'registry' -and $_.path -eq $reg.path -and $_.name -eq $reg.name } | Select-Object -First 1

            if ($null -ne $capReg) {
                if (($capReg.isRemoveKeyHint -or $reg.originalValue -eq '<RemoveKey>') -and (-not $capReg.keyExisted)) {
                    Set-RegistryEntryValue -Path $reg.path -Name $reg.name -Type $reg.type -Value '<RemoveKey>'
                }
                elseif (-not $capReg.existed) {
                    if ($reg.originalValue -eq '<RemoveKey>') {
                        Set-RegistryEntryValue -Path $reg.path -Name $reg.name -Type $reg.type -Value '<RemoveKey>'
                    }
                    else {
                        Set-RegistryEntryValue -Path $reg.path -Name $reg.name -Type $reg.type -Value '<RemoveEntry>'
                    }
                }
                else {
                    $restoreType = if ($capReg.type) { $capReg.type } else { $reg.type }
                    Set-RegistryEntryValue -Path $reg.path -Name $reg.name -Type $restoreType -Value $capReg.value
                }
            }
            else {
                Set-RegistryEntryValue -Path $reg.path -Name $reg.name -Type $reg.type -Value $reg.originalValue
            }
        }

        Remove-CapturedState -Id $Id
        return $true
    }
}
