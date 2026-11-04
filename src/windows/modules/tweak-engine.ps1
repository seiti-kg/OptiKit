# Motor de execução e reversão (Apply / Undo) de Tweaks: Registro, Serviços, Tarefas Agendadas, Appx e Helpers

#region dev-only
if (-not (Get-Command Write-OptimizerLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\core\logger.ps1')
}
if (-not (Get-Command Save-CapturedState -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\core\backup.ps1')
}
if (-not (Get-Command Get-OptiKitHardware -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'hardware-utils.ps1')
}
if (-not (Get-Command Install-OptiKitApp -ErrorAction SilentlyContinue)) {
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
    'Set-OptiKitSmartPowerPlan',
    'Enable-OptiKitUltimatePowerPlan',
    'Restore-OptiKitPowerPlan',
    'Disable-OptiKitHibernation',
    'Enable-OptiKitHibernation',
    'Optimize-UsbPower',
    'Restore-UsbPower',
    'Remove-OptiKitOneDrive',
    'Install-OptiKitOneDrive',
    'Enable-OptiKitWindowedGameOptimizations',
    'Disable-OptiKitWindowedGameOptimizations',
    'Set-OptiKitTargetRelease',
    'Restore-OptiKitTargetRelease',
    'Disable-OptiKitReservedStorage',
    'Enable-OptiKitReservedStorage'
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
        [AllowEmptyString()]
        [string]$StoreId,

        [ValidateSet('Apply', 'Undo')]
        [string]$Mode = 'Apply'
    )

    if ($script:ProtectedAppxPackages -contains $PackageName) {
        throw "Pacote Appx '$PackageName' é protegido e não pode ser removido."
    }

    if ($Mode -eq 'Apply') {
        Invoke-Mutation -Description ("Remover pacote Appx '{0}' (usuários + provisionamento)" -f $PackageName) -Action {
            $wg = Test-WingetAvailable
            if ($wg.Available -and -not [string]::IsNullOrWhiteSpace($StoreId)) {
                & $wg.Path show --id $StoreId --source msstore --exact --accept-source-agreements *> $null
                if ($LASTEXITCODE -ne 0) {
                    Write-OptimizerLog -Level WARN -Message ("Pacote '{0}' (Store ID: {1}) não está disponível na Store; o Undo poderá falhar ao reinstalar." -f $PackageName, $StoreId)
                }
            }

            $pkgs = Get-AppxPackage -AllUsers -Name "*$PackageName*" -ErrorAction SilentlyContinue
            foreach ($p in $pkgs) {
                Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction SilentlyContinue
            }
            $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like "*$PackageName*" }
            foreach ($pr in $prov) {
                Remove-AppxProvisionedPackage -Online -PackageName $pr.PackageName -ErrorAction SilentlyContinue | Out-Null
            }

            $remainingUser = @(Get-AppxPackage -AllUsers -Name "*$PackageName*" -ErrorAction SilentlyContinue)
            $remainingProv = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like "*$PackageName*" })
            if ($remainingUser.Count -gt 0 -or $remainingProv.Count -gt 0) {
                $remainingNames = @($remainingUser | ForEach-Object { $_.PackageFullName }) +
                    @($remainingProv | ForEach-Object { $_.PackageName })
                throw ("Pacote Appx '{0}' ainda presente após a remoção: {1}" -f $PackageName, ($remainingNames -join '; '))
            }
        } | Out-Null
    }
    else {
        Invoke-Mutation -Description ("Reinstalar pacote Appx '{0}' (Store ID: {1}) via Winget" -f $PackageName, $StoreId) -Action {
            if ([string]::IsNullOrWhiteSpace($StoreId)) {
                throw ("Store ID vazio para o pacote Appx '{0}'; não é possível reinstalar via Winget." -f $PackageName)
            }

            $wg = Test-WingetAvailable
            if (-not $wg.Available) {
                throw ("Winget indisponível para reinstalar '{0}' ({1})." -f $PackageName, $StoreId)
            }

            $argsList = @('install', '--id', $StoreId, '--source', 'msstore', '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements')
            $proc = Start-Process -FilePath $wg.Path -ArgumentList $argsList -NoNewWindow -Wait -PassThru
            $exitCode = [int64]$proc.ExitCode
            if ($exitCode -gt [int]::MaxValue) {
                $exitCode -= 4294967296
            }
            if ($exitCode -ne 0 -and $exitCode -ne -1978335189 -and $exitCode -ne 3010) {
                throw ("Winget falhou ao reinstalar '{0}' ({1}). Código de saída: {2}." -f $PackageName, $StoreId, $exitCode)
            }

            if (-not (Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue)) {
                throw ("Pacote Appx '{0}' não encontrado após a reinstalação via Winget." -f $PackageName)
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
        $hardware = Get-OptiKitHardware
        $blockReason = Test-OptiKitTweakBlocked -Tweak $Tweak -Hardware $hardware
        if ($blockReason) {
            Write-OptimizerLog -Level WARN -Message ("Tweak '{0}' ignorado neste hardware: {1}" -f $Id, $blockReason)
            return $false
        }

        if (-not (Test-OptiKitTweakSupported -Tweak $Tweak -Hardware $hardware)) {
            $osTag = if ($hardware.IsWin11) { 'Win11' } else { 'Win10' }
            $supportedOs = if ($null -ne $Tweak.osSupport) { @($Tweak.osSupport | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) } else { @() }
            $osText = if ($supportedOs.Count -gt 0) { $supportedOs -join '/' } else { $osTag }
            $buildText = if ($null -ne $Tweak.minBuild) { " build $($Tweak.minBuild)+" } else { '' }
            Write-OptimizerLog -Level WARN -Message ("Tweak '{0}' ignorado: requer {1}{2}; sistema atual: {3} (build {4})." -f $Id, $osText, $buildText, $osTag, $hardware.OsBuild)
            return $false
        }

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
            $capApx = $capturedList | Where-Object { $_.kind -eq 'appx' -and $_.name -eq $apx.name } | Select-Object -First 1
            if ($null -ne $capApx -and -not [bool]$capApx.existed) {
                Write-OptimizerLog -Level INFO -Message ("Pacote Appx '{0}' não estava instalado antes do tweak; nada a reinstalar." -f $apx.name)
                continue
            }
            if ($null -eq $capApx) {
                Write-OptimizerLog -Level WARN -Message ("Sem captura de estado para o pacote Appx '{0}'; tentando reinstalar, mas o estado original é desconhecido." -f $apx.name)
            }
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

function Enable-OptiKitWindowedGameOptimizations {
    [CmdletBinding()]
    param(
        [string]$RegistryPath = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    )

    $valueName = 'DirectXUserGlobalSettings'
    $stateId = 'DirectXGlobalSettings'
    $current = Get-RegistryEntryState -Path $RegistryPath -Name $valueName -FallbackType 'String'

    Save-CapturedState -Id $stateId -CapturedItems @(
        @{
            kind       = 'registry'
            path       = $RegistryPath
            name       = $valueName
            keyExisted = [bool]$current.KeyExisted
            existed    = [bool]$current.ValueExisted
            type       = 'String'
            value      = $current.Value
        }
    )

    $tokens = New-Object 'System.Collections.Generic.List[string]'
    if ($current.ValueExisted -and -not [string]::IsNullOrWhiteSpace([string]$current.Value)) {
        foreach ($token in ([string]$current.Value -split ';')) {
            $clean = $token.Trim()
            if (-not [string]::IsNullOrWhiteSpace($clean) -and $clean -notmatch '^SwapEffectUpgradeEnable=') {
                [void]$tokens.Add($clean)
            }
        }
    }
    [void]$tokens.Add('SwapEffectUpgradeEnable=1')
    $newValue = ($tokens -join ';') + ';'

    Set-RegistryEntryValue -Path $RegistryPath -Name $valueName -Type 'String' -Value $newValue
}

function Disable-OptiKitWindowedGameOptimizations {
    [CmdletBinding()]
    param()

    $stateId = 'DirectXGlobalSettings'
    $captured = Get-CapturedState -Id $stateId
    if ($captured -and $captured.captured -and $captured.captured.Count -gt 0) {
        $item = $captured.captured[0]
        if ($item.existed) {
            Set-RegistryEntryValue -Path $item.path -Name $item.name -Type 'String' -Value $item.value
        }
        elseif ($item.keyExisted) {
            Set-RegistryEntryValue -Path $item.path -Name $item.name -Type 'String' -Value '<RemoveEntry>'
        }
        else {
            Set-RegistryEntryValue -Path $item.path -Name $item.name -Type 'String' -Value '<RemoveKey>'
        }
    }
    Remove-CapturedState -Id $stateId
}

function Test-OptiKitWindowedGameOptimizations {
    [CmdletBinding()]
    param(
        [string]$RegistryPath = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    )

    $state = Get-RegistryEntryState -Path $RegistryPath -Name 'DirectXUserGlobalSettings' -FallbackType 'String'
    return ($state.ValueExisted -and ([string]$state.Value -match '(?i)(^|;)SwapEffectUpgradeEnable=1(;|$)'))
}

function ConvertTo-OptiKitProfile {
    [CmdletBinding()]
    param(
        [string[]]$Tweaks = @(),
        [string[]]$GameOptimizations = @(),
        [string[]]$Apps = @(),
        [string]$Preset = ''
    )

    $version = if ($script:OptiKitVersion) { [string]$script:OptiKitVersion } else { '0.2.1' }
    return [pscustomobject]@{
        schemaVersion     = 1
        optikitVersion    = $version
        createdAt         = (Get-Date -Format 'o')
        preset            = $Preset
        tweaks            = @($Tweaks | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        gameOptimizations = @($GameOptimizations | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        apps              = @($Apps | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
}

function Assert-OptiKitSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Configs,
        [Parameter(Mandatory = $true)][pscustomobject]$Selection
    )

    foreach ($tweakId in @($Selection.Tweaks)) {
        if ([string]::IsNullOrWhiteSpace($tweakId)) { continue }
        if (-not $Configs.WinTweaks.PSObject.Properties[$tweakId]) {
            throw ("Tweak '{0}' não existe no catálogo." -f $tweakId)
        }
    }

    foreach ($gameOptId in @($Selection.GameOptimizations)) {
        if ([string]::IsNullOrWhiteSpace($gameOptId)) { continue }
        $found = $false
        foreach ($gameProfile in $Configs.GameProfiles.PSObject.Properties) {
            foreach ($optimization in @($gameProfile.Value.optimizations)) {
                if ($optimization.id -eq $gameOptId) {
                    $found = $true
                    break
                }
            }
            if ($found) { break }
        }
        if (-not $found) {
            throw ("Otimização de jogo '{0}' não existe no catálogo." -f $gameOptId)
        }
    }

    foreach ($appId in @($Selection.Apps)) {
        if ([string]::IsNullOrWhiteSpace($appId)) { continue }
        if (-not $Configs.Apps.PSObject.Properties[$appId]) {
            throw ("Aplicativo '{0}' não existe no catálogo." -f $appId)
        }
    }
}

function ConvertFrom-OptiKitProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][hashtable]$Configs
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw ("Arquivo de perfil não encontrado: {0}" -f $Path)
    }

    $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    try {
        $profileData = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw ("Perfil JSON inválido: {0}" -f $_.Exception.Message)
    }
    if ($null -eq $profileData) {
        throw 'Perfil JSON vazio.'
    }

    $schema = if ($null -ne $profileData.schemaVersion) { [int]$profileData.schemaVersion } else { 1 }
    if ($schema -gt 1) {
        throw ("Perfil com schemaVersion {0} não é suportado por esta versão do OptiKit." -f $schema)
    }

    $profileVersionRaw = [string]$profileData.optikitVersion
    if (-not [string]::IsNullOrWhiteSpace($profileVersionRaw)) {
        try {
            $profileVersion = [version]$profileVersionRaw
            if ($script:OptiKitVersion) {
                $localVersion = [version]$script:OptiKitVersion
                if ($profileVersion -gt $localVersion) {
                    Write-OptimizerLog -Level WARN -Message ("Perfil criado pelo OptiKit v{0}; esta versão é v{1}. IDs desconhecidos serão rejeitados." -f $profileVersion, $localVersion)
                }
            }
        }
        catch {
            Write-Verbose ("optikitVersion inválido no perfil: {0}" -f $profileVersionRaw)
        }
    }

    $selection = [pscustomobject]@{
        Preset            = [string]$profileData.preset
        Tweaks            = @($profileData.tweaks | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        GameOptimizations = @($profileData.gameOptimizations | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        Apps              = @($profileData.apps | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    Assert-OptiKitSelection -Configs $Configs -Selection $selection
    return $selection
}

function Resolve-OptiKitSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Configs,
        [string]$PresetKey,
        [string]$ConfigPath
    )

    if (-not [string]::IsNullOrWhiteSpace($PresetKey) -and -not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        throw 'Use apenas -Preset ou -Config, não ambos.'
    }

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        return ConvertFrom-OptiKitProfile -Path $ConfigPath -Configs $Configs
    }

    if ([string]::IsNullOrWhiteSpace($PresetKey)) {
        throw 'Informe -Preset ou -Config para o modo desatendido.'
    }

    $presetProp = $Configs.Presets.PSObject.Properties[$PresetKey]
    if (-not $presetProp) {
        throw ("Preset '{0}' não encontrado em presets.json." -f $PresetKey)
    }

    $preset = $presetProp.Value
    $selection = [pscustomobject]@{
        Preset            = $PresetKey
        Tweaks            = @($preset.tweaks)
        GameOptimizations = @($preset.gameOptimizations)
        Apps              = @($preset.apps)
    }

    Assert-OptiKitSelection -Configs $Configs -Selection $selection
    return $selection
}

function Get-OptiKitStateUndoPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$StateData,
        [Parameter(Mandatory = $true)][hashtable]$Configs
    )

    $gameOptions = @{}
    foreach ($gameProfile in $Configs.GameProfiles.PSObject.Properties) {
        foreach ($optimization in @($gameProfile.Value.optimizations)) {
            $gameOptions[$optimization.id] = [pscustomobject]@{
                Profile      = $gameProfile.Value
                Optimization = $optimization
            }
        }
    }

    $plan = New-Object 'System.Collections.Generic.List[pscustomobject]'
    foreach ($key in $StateData.Keys) {
        $record = $StateData[$key]
        $appliedAt = $null
        if ($record -and $record.appliedAt) {
            try {
                $appliedAt = [datetime]$record.appliedAt
            }
            catch {
                Write-Verbose ("appliedAt inválido para '{0}': {1}" -f $key, $_.Exception.Message)
            }
        }

        $entry = [pscustomobject]@{
            Key          = $key
            AppliedAt    = $appliedAt
            Kind         = 'Unknown'
            Tweak        = $null
            Profile      = $null
            Optimization = $null
        }

        if ($Configs.WinTweaks.PSObject.Properties[$key]) {
            $entry.Kind = 'Tweak'
            $entry.Tweak = $Configs.WinTweaks.$key
        }
        elseif ($gameOptions.ContainsKey($key)) {
            $entry.Kind = 'GameOpt'
            $entry.Profile = $gameOptions[$key].Profile
            $entry.Optimization = $gameOptions[$key].Optimization
        }
        elseif ($key -eq 'PowerPlanOriginal') { $entry.Kind = 'PowerPlan' }
        elseif ($key -eq 'UsbPowerOptimization') { $entry.Kind = 'UsbPower' }
        elseif ($key -eq 'NetworkAdapterGaming') { $entry.Kind = 'Network' }
        elseif ($key -eq 'DirectXGlobalSettings') { $entry.Kind = 'DirectX' }
        elseif ($key -eq 'TargetReleaseVersion') { $entry.Kind = 'TargetRelease' }
        elseif ($key -eq 'ReservedStorage') { $entry.Kind = 'ReservedStorage' }

        [void]$plan.Add($entry)
    }

    return @($plan | Sort-Object -Property @{ Expression = { if ($_.AppliedAt) { $_.AppliedAt } else { [datetime]::MinValue } }; Descending = $true })
}

function Invoke-OptiKitRevertAll {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Configs
    )

    $state = Read-OptiKitStateFile
    if ($state.Count -eq 0) {
        Write-OptimizerLog -Level INFO -Message 'Nenhum estado capturado para reverter.'
        return 0
    }

    $plan = Get-OptiKitStateUndoPlan -StateData $state -Configs $Configs
    $failures = 0
    $reverted = 0

    foreach ($entry in $plan) {
        if ($entry.Kind -eq 'Unknown') {
            Write-OptimizerLog -Level WARN -Message ("Estado '{0}' sem rotina de reversão conhecida; entrada mantida." -f $entry.Key)
            continue
        }

        try {
            switch ($entry.Kind) {
                'Tweak' { Invoke-Tweak -Id $entry.Key -Tweak $entry.Tweak -Mode 'Undo' | Out-Null }
                'GameOpt' { Invoke-GameOptimization -ProfileConfig $entry.Profile -Optimization $entry.Optimization -Mode 'Undo' | Out-Null }
                'PowerPlan' { Restore-OptiKitPowerPlan }
                'UsbPower' { Restore-UsbPower }
                'Network' { Optimize-NetworkAdapterGaming -Mode 'Undo' }
                'DirectX' { Disable-OptiKitWindowedGameOptimizations }
                'TargetRelease' { Restore-OptiKitTargetRelease }
                'ReservedStorage' { Enable-OptiKitReservedStorage }
            }
            $reverted++
        }
        catch {
            $failures++
            Write-OptimizerLog -Level WARN -Message ("Falha ao reverter '{0}': {1}" -f $entry.Key, $_.Exception.Message)
        }
    }

    Write-OptimizerLog -Level OK -Message ("Reverter Tudo concluído: {0} entrada(s) revertida(s), {1} falha(s)." -f $reverted, $failures)
    if ($failures -gt 0) {
        return 1
    }
    return 0
}
