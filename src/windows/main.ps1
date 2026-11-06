# Inicializador principal do OptiKit (Windows): UAC, STA, Runspace Worker assíncrono e ciclo de vida da GUI WPF

#region dev-only
[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$Preset,
    [switch]$SmokeTest,
    [switch]$NoElevate,
    [switch]$Relaunched,
    [switch]$Apply,
    [switch]$Silent,
    [string]$Config
)

$devRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'core\logger.ps1')
. (Join-Path $PSScriptRoot 'core\backup.ps1')
. (Join-Path $PSScriptRoot 'modules\hardware-utils.ps1')
. (Join-Path $PSScriptRoot 'modules\winget-engine.ps1')
. (Join-Path $PSScriptRoot 'modules\tweak-engine.ps1')
. (Join-Path $PSScriptRoot 'modules\game-engine.ps1')
. (Join-Path $PSScriptRoot 'modules\maintenance.ps1')
. (Join-Path $PSScriptRoot 'modules\network-engine.ps1')
. (Join-Path $PSScriptRoot 'modules\startup-manager.ps1')
. (Join-Path $PSScriptRoot 'core\state-checker.ps1')
. (Join-Path $PSScriptRoot 'modules\diagnostics.ps1')
. (Join-Path $PSScriptRoot 'ui\ui-builder.ps1')
#endregion

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-OptiKitRelaunch {
    param(
        [switch]$AsAdmin,
        [switch]$PassDryRun,
        [string]$PassPreset,
        [switch]$PassSmokeTest,
        [switch]$PassNoElevate,
        [switch]$PassApply,
        [switch]$PassSilent,
        [string]$PassConfig
    )

    $targetScript = $null
    $createdTemp = $false
    if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
        $existingContent = [System.IO.File]::ReadAllText($PSCommandPath, [System.Text.Encoding]::UTF8)
        if ($existingContent -match 'function\s+Start-OptiKitMain') {
            $targetScript = $PSCommandPath
        }
    }

    if (-not $targetScript) {
        $fnCmd = Get-Command -Name 'Invoke-OptiKitRelaunch' -CommandType Function -ErrorAction Stop
        $rootAst = $fnCmd.ScriptBlock.Ast
        while ($null -ne $rootAst.Parent) {
            $rootAst = $rootAst.Parent
        }
        $scriptBody = $rootAst.Extent.Text
        if ([string]::IsNullOrWhiteSpace($scriptBody) -or ($scriptBody -notmatch 'function\s+Start-OptiKitMain') -or ($scriptBody -notmatch 'function\s+Initialize-OptiKitUi')) {
            throw 'Não foi possível reconstruir o script completo na memória para elevação UAC. Abra o PowerShell já como Administrador e execute novamente.'
        }
        $targetScript = Join-Path $env:TEMP ("optikit_bootstrap_" + [Guid]::NewGuid().ToString('N') + ".ps1")
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($targetScript, $scriptBody, $utf8Bom)
        $createdTemp = $true
    }

    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $psExe)) {
        $psExe = 'powershell.exe'
    }

    $argList = New-Object 'System.Collections.Generic.List[string]'
    [void]$argList.Add('-NoProfile')
    [void]$argList.Add('-ExecutionPolicy')
    [void]$argList.Add('Bypass')
    [void]$argList.Add('-STA')
    [void]$argList.Add('-File')
    [void]$argList.Add(('"{0}"' -f $targetScript))
    [void]$argList.Add('-Relaunched')

    if ($PassDryRun) { [void]$argList.Add('-DryRun') }
    if (-not [string]::IsNullOrWhiteSpace($PassPreset)) {
        [void]$argList.Add('-Preset')
        [void]$argList.Add(('"{0}"' -f $PassPreset))
    }
    if ($PassSmokeTest) { [void]$argList.Add('-SmokeTest') }
    if ($PassNoElevate) { [void]$argList.Add('-NoElevate') }
    if ($PassApply) { [void]$argList.Add('-Apply') }
    if ($PassSilent) { [void]$argList.Add('-Silent') }
    if (-not [string]::IsNullOrWhiteSpace($PassConfig)) {
        [void]$argList.Add('-Config')
        [void]$argList.Add(('"{0}"' -f $PassConfig))
    }

    $startParams = @{
        FilePath     = $psExe
        ArgumentList = ($argList -join ' ')
        Wait         = $true
        PassThru     = $true
    }
    if ($AsAdmin) {
        $startParams['Verb'] = 'RunAs'
    }

    try {
        $proc = Start-Process @startParams
        $code = if ($null -ne $proc.ExitCode) { $proc.ExitCode } else { 0 }
        exit $code
    }
    catch {
        Write-Warning ("Elevação UAC cancelada ou falhou: {0}" -f $_.Exception.Message)
        exit 1
    }
    finally {
        if ($createdTemp -and $targetScript -and (Test-Path -LiteralPath $targetScript)) {
            Remove-Item -LiteralPath $targetScript -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-OptiKitCatalogConfigs {
    if ($script:EmbeddedAppsJson -and $script:EmbeddedWinTweaksJson -and $script:EmbeddedGameProfilesJson -and $script:EmbeddedGameLogosJson -and $script:EmbeddedPresetsJson -and $script:EmbeddedLogoBase64) {
        return @{
            Apps         = $script:EmbeddedAppsJson | ConvertFrom-Json
            WinTweaks    = $script:EmbeddedWinTweaksJson | ConvertFrom-Json
            GameProfiles = $script:EmbeddedGameProfilesJson | ConvertFrom-Json
            GameLogos    = $script:EmbeddedGameLogosJson | ConvertFrom-Json
            Presets      = $script:EmbeddedPresetsJson | ConvertFrom-Json
            ThemeXaml    = $script:EmbeddedThemeXaml
            LogoBase64   = $script:EmbeddedLogoBase64
        }
    }

    $baseDir = if ($devRoot) { $devRoot } else { Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent }
    return @{
        Apps         = [System.IO.File]::ReadAllText((Join-Path $baseDir 'config\apps.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        WinTweaks    = [System.IO.File]::ReadAllText((Join-Path $baseDir 'config\win-tweaks.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        GameProfiles = [System.IO.File]::ReadAllText((Join-Path $baseDir 'config\game-profiles.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        GameLogos    = [System.IO.File]::ReadAllText((Join-Path $baseDir 'config\game-logos.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        Presets      = [System.IO.File]::ReadAllText((Join-Path $baseDir 'config\presets.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        ThemeXaml    = [System.IO.File]::ReadAllText((Join-Path $baseDir 'src\windows\ui\theme.xaml'), [System.Text.Encoding]::UTF8)
        LogoBase64   = if (Test-Path -LiteralPath (Join-Path $baseDir 'assets\optikit_logo_ui.png')) {
            [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $baseDir 'assets\optikit_logo_ui.png')))
        } else { $null }
    }
}

function Start-OptiKitWorkerTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$SyncHash,
        [Parameter(Mandatory = $true)][scriptblock]$WorkerScript,
        [hashtable]$Arguments = @{}
    )

    if ($SyncHash.IsBusy) {
        Write-OptimizerLog -Level WARN -Message 'Uma operação já está em andamento. Aguarde a conclusão.'
        return
    }

    $SyncHash.IsBusy = $true
    $SyncHash.CancelRequest = $false
    $SyncHash.Progress = 5

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $fnNames = @(
        'Initialize-OptiKitEnvironment', 'Write-OptimizerLog', 'Invoke-Mutation',
        'New-OptiKitBackupSession', 'ConvertTo-RegExePath', 'Export-RegistryKeyBackup',
        'Read-OptiKitStateFile', 'Write-OptiKitStateFile', 'Save-CapturedState',
        'Get-CapturedState', 'Remove-CapturedState', 'New-OptiKitRestorePoint',
        'Get-OptiKitHardware', 'Resolve-OptiKitCpuFlags', 'Get-OptiKitGpuVramBytes', 'Test-OptiKitHagsVramConstrained',
        'Get-ActivePowerPlanGuid', 'Set-OptiKitSmartPowerPlan',
        'Enable-OptiKitUltimatePowerPlan', 'Restore-OptiKitPowerPlan',
        'Test-OptiKitSmartPowerPlan', 'Test-OptiKitUltimatePowerPlan',
        'Disable-OptiKitHibernation', 'Enable-OptiKitHibernation',
        'Optimize-UsbPower', 'Restore-UsbPower', 'Test-UsbPowerOptimized',
        'Test-OptiKitTweakBlocked', 'Test-OptiKitTweakSupported', 'Enable-OptiKitWindowedGameOptimizations',
        'Disable-OptiKitWindowedGameOptimizations', 'Test-OptiKitWindowedGameOptimizations',
        'Set-OptiKitTargetRelease', 'Restore-OptiKitTargetRelease', 'Test-OptiKitTargetRelease',
        'Disable-OptiKitReservedStorage', 'Enable-OptiKitReservedStorage', 'Test-OptiKitReservedStorage',
        'Get-OptiKitHardwareDiagnostics', 'New-OptiKitDiagnosticItem',
        'Get-OptiKitDiagnosticBios', 'Get-OptiKitDiagnosticDisk', 'Get-OptiKitDiagnosticStability',
        'Test-OptiKitPendingReboot', 'Get-OptiKitDiagnosticPendingReboot', 'Get-OptiKitDiagnosticDefender',
        'Format-OptiKitDiagnosticSize',
        'Get-OptiKitDiagnosticRam', 'Get-OptiKitDisplayModes', 'Get-OptiKitDiagnosticMonitor',
        'Get-OptiKitDiagnosticDeviceGuard', 'Get-OptiKitDiagnosticGamingToggles',
        'Get-OptiKitDiagnosticWindowsGamingState', 'Get-OptiKitEnergySaverState',
        'Get-OptiKitDiagnosticX3dService', 'Get-OptiKitDiagnosticGpuDriver',
        'Get-OptiKitStateUndoPlan', 'Invoke-OptiKitRevertAll',
        'Test-OptiKitUpdateAvailable', 'Export-OptiKitReport',
        'Test-WingetAvailable', 'Install-WingetBootstrap', 'Install-OptiKitApp',
        'Invoke-OptiKitWingetCommand', 'Invoke-OptiKitWingetUpgrade',
        'Test-OneDriveKfmActive', 'Remove-OptiKitOneDrive', 'Install-OptiKitOneDrive', 'Test-OptiKitOneDriveRemoved',
        'Test-AntiCheatGuardrail', 'Get-RegistryEntryState', 'Set-RegistryEntryValue',
        'Set-ServiceStartupState', 'Set-ScheduledTaskState', 'Invoke-AppxRemoval',
        'Invoke-TweakHelperScript', 'Invoke-Tweak',
        'Find-GameExecutable', 'Set-AppCompatFlags', 'Set-DirectXGpuPreference',
        'Optimize-NetworkAdapterGaming', 'Disable-RiotClientStartup', 'Clear-ShaderCache',
        'Invoke-GameOptimization', 'Test-GameOptimizationApplied',
        'Invoke-NetworkReset', 'Invoke-NativeStep', 'Invoke-CancelableProcess', 'Invoke-SystemIntegrityRepair', 'Clear-TemporaryFiles',
        'Restart-OptiKitToUefi',
        'Clear-OptiKitDirectory', 'Invoke-AdvancedCleanup',
        'Get-OptiKitDohProviders', 'Get-OptiKitDnsAdapters', 'Test-OptiKitDohSupported',
        'Set-OptiKitDnsFamily', 'Remove-OptiKitDohEncryption', 'Set-OptiKitDohEncryption', 'Set-OptiKitDohProvider', 'Restore-OptiKitDns',
        'Get-OptiKitStartupItems', 'Set-OptiKitStartupItemState',
        'Test-TweakApplied', 'Get-AllTweaksState'
    )

    foreach ($fnName in $fnNames) {
        $cmd = Get-Command -Name $fnName -CommandType Function -ErrorAction SilentlyContinue
        if ($cmd) {
            $entry = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry($fnName, $cmd.Definition)
            [void]$iss.Commands.Add($entry)
        }
    }

    $runspace = [runspacefactory]::CreateRunspace($iss)
    $runspace.ApartmentState = 'STA'
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable('SyncHash', $SyncHash)
    $runspace.SessionStateProxy.SetVariable('WorkerArgs', $Arguments)
    $runspace.SessionStateProxy.SetVariable('ParentOptiKit', $script:OptiKit)
    $runspace.SessionStateProxy.SetVariable('AllowedTweakScripts', $script:AllowedTweakScripts)
    $runspace.SessionStateProxy.SetVariable('AllowedCheckScripts', $script:AllowedCheckScripts)
    $runspace.SessionStateProxy.SetVariable('AllowedGameActions', $script:AllowedGameActions)
    $runspace.SessionStateProxy.SetVariable('ProtectedAppxPackages', $script:ProtectedAppxPackages)
    $runspace.SessionStateProxy.SetVariable('OptiKitVersion', $script:OptiKitVersion)
    $runspace.SessionStateProxy.SetVariable('OptiKitRepo', $script:OptiKitRepo)

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace

    $wrapper = {
        $script:OptiKit = $ParentOptiKit
        $script:ProtectedAppxPackages = @($ProtectedAppxPackages)
        $script:AllowedTweakScripts = @($AllowedTweakScripts)
        $script:AllowedGameActions = @($AllowedGameActions)
        $script:AllowedCheckScripts = @($AllowedCheckScripts)
        $script:OptiKitVersion = $OptiKitVersion
        $script:OptiKitRepo = $OptiKitRepo

        try {
            & ([scriptblock]::Create($WorkerArgs.ScriptText))
        }
        catch {
            Write-OptimizerLog -Level ERROR -Message ("Erro na tarefa em 2º plano: {0}" -f $_.Exception.Message)
        }
        finally {
            $SyncHash.Progress = 100
            $SyncHash.IsBusy = $false
        }
    }

    $Arguments['ScriptText'] = $WorkerScript.ToString()
    [void]$ps.AddScript($wrapper)
    $SyncHash.ActivePowerShell = $ps
    $SyncHash.ActiveRunspace = $runspace
    $SyncHash.AsyncResult = $ps.BeginInvoke()
}

function Invoke-OptiKitSilentMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Configs,
        [Parameter(Mandatory = $true)][pscustomobject]$Selection,
        [switch]$ApplyMode
    )

    $tweaks = @($Selection.Tweaks)
    $gameOpts = @($Selection.GameOptimizations)
    $apps = @($Selection.Apps)

    Write-OptimizerLog -Level INFO -Message ("Modo desatendido: {0} tweak(s), {1} otimização(ões) de jogo, {2} app(s)." -f $tweaks.Count, $gameOpts.Count, $apps.Count)

    if (-not $ApplyMode) {
        Write-OptimizerLog -Level INFO -Message 'Nenhuma alteração será feita (-Apply não informado). Itens resolvidos:'
        foreach ($id in $tweaks) { Write-OptimizerLog -Level INFO -Message ("  [Tweak] {0}" -f $id) }
        foreach ($id in $gameOpts) { Write-OptimizerLog -Level INFO -Message ("  [Jogo] {0}" -f $id) }
        foreach ($id in $apps) { Write-OptimizerLog -Level INFO -Message ("  [App] {0}" -f $id) }
        return 0
    }

    New-OptiKitBackupSession | Out-Null
    if ($tweaks.Count -gt 0 -or $gameOpts.Count -gt 0) {
        New-OptiKitRestorePoint -Description 'OptiKit - Modo desatendido' | Out-Null
    }

    $failures = 0
    $executed = 0
    $skipped = 0

    foreach ($tweakId in $tweaks) {
        try {
            $result = Invoke-Tweak -Id $tweakId -Tweak $Configs.WinTweaks.$tweakId -Mode 'Apply'
            if ($result) {
                $executed++
            }
            else {
                $skipped++
                Write-OptimizerLog -Level WARN -Message ("Tweak '{0}' não aplicado (bloqueado neste hardware ou sem efeito)." -f $tweakId)
            }
        }
        catch {
            $failures++
            Write-OptimizerLog -Level ERROR -Message ("Falha no tweak '{0}': {1}" -f $tweakId, $_.Exception.Message)
        }
    }

    foreach ($gameOptId in $gameOpts) {
        $profileConfig = $null
        $optimization = $null
        foreach ($gameProfile in $Configs.GameProfiles.PSObject.Properties) {
            foreach ($candidate in @($gameProfile.Value.optimizations)) {
                if ($candidate.id -eq $gameOptId) {
                    $profileConfig = $gameProfile.Value
                    $optimization = $candidate
                    break
                }
            }
            if ($optimization) { break }
        }

        if (-not $optimization) {
            $failures++
            Write-OptimizerLog -Level ERROR -Message ("Otimização de jogo '{0}' não encontrada." -f $gameOptId)
            continue
        }

        try {
            $applied = Invoke-GameOptimization -ProfileConfig $profileConfig -Optimization $optimization -Mode 'Apply'
            if ($applied) {
                $executed++
            }
            else {
                $skipped++
                Write-OptimizerLog -Level WARN -Message ("Otimização '{0}' ignorada (executável não encontrado ou ação indisponível)." -f $gameOptId)
            }
        }
        catch {
            $failures++
            Write-OptimizerLog -Level ERROR -Message ("Falha na otimização '{0}': {1}" -f $gameOptId, $_.Exception.Message)
        }
    }

    foreach ($appId in $apps) {
        try {
            $ok = Install-OptiKitApp -AppKey $appId -AppConfig $Configs.Apps.$appId
            if ($ok) {
                $executed++
            }
            else {
                $failures++
            }
        }
        catch {
            $failures++
            Write-OptimizerLog -Level ERROR -Message ("Falha ao instalar '{0}': {1}" -f $appId, $_.Exception.Message)
        }
    }

    $state = Get-AllTweaksState -TweaksConfig $Configs.WinTweaks -GameProfilesConfig $Configs.GameProfiles
    $appliedState = @($state.Tweaks.Values | Where-Object { $_ -eq 'Applied' }).Count
    Write-OptimizerLog -Level OK -Message ("Modo desatendido concluído: {0} aplicado(s), {1} ignorado(s) por hardware/sem efeito, {2} falha(s), {3} ajuste(s) ativo(s)." -f $executed, $skipped, $failures, $appliedState)
    Write-OptimizerLog -Level INFO -Message ("Log: {0}" -f $script:OptiKit.LogFile)

    if ($failures -gt 0) {
        return 1
    }
    return 0
}

function Start-OptiKitMain {
    [CmdletBinding()]
    param(
        [switch]$DryRunMode,
        [string]$InitialPreset,
        [switch]$IsSmokeTest,
        [switch]$SkipElevation,
        [switch]$IsRelaunched,
        [switch]$ApplyMode,
        [switch]$SilentMode,
        [string]$ConfigPath
    )

    $needsAdmin = (-not $DryRunMode -and -not $IsSmokeTest -and -not $SkipElevation -and (-not (Test-IsAdministrator)) -and ((-not $SilentMode) -or $ApplyMode))
    $needsSta = (-not $SilentMode) -and ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA')

    if ($needsAdmin -or $needsSta) {
        if ($IsRelaunched) {
            throw 'O OptiKit já tentou reinicializar em modo Administrador/STA uma vez e foi interrompido para evitar loop. Abra o Windows PowerShell como Administrador.'
        }
        Invoke-OptiKitRelaunch -AsAdmin:$needsAdmin -PassDryRun:$DryRunMode -PassPreset $InitialPreset -PassSmokeTest:$IsSmokeTest -PassNoElevate:$SkipElevation -PassApply:$ApplyMode -PassSilent:$SilentMode -PassConfig $ConfigPath
        return
    }

    if ($SilentMode) {
        Initialize-OptiKitEnvironment -DryRun:$DryRunMode | Out-Null
        $script:OptiKit.ConsoleOutput = $true
        $configs = Get-OptiKitCatalogConfigs
        try {
            $selection = Resolve-OptiKitSelection -Configs $configs -PresetKey $InitialPreset -ConfigPath $ConfigPath
        }
        catch {
            Write-OptimizerLog -Level ERROR -Message $_.Exception.Message
            exit 2
        }
        $code = Invoke-OptiKitSilentMode -Configs $configs -Selection $selection -ApplyMode:$ApplyMode
        exit $code
    }

    $sync = [hashtable]::Synchronized(@{
        LogQueue             = New-Object 'System.Collections.Concurrent.ConcurrentQueue[psobject]'
        Progress             = 0
        StatusText           = 'Inicializando OptiKit...'
        IsBusy               = $false
        CancelRequest        = $false
        PendingStateReport   = $null
        PendingDiagnosticsReport = $null
        PendingDiagnosticsStart  = $false
        PendingUpdateInfo    = $null
        PendingStartupItems  = $null
        ActivePowerShell     = $null
        ActiveRunspace       = $null
        AsyncResult          = $null
        SessionCounts        = @{ Applied = 0; Skipped = 0; Failed = 0 }
    })

    if ($IsSmokeTest) {
        $smokeDataDir = Join-Path $env:TEMP ("optikit_smoke_" + [Guid]::NewGuid().ToString('N'))
        Initialize-OptiKitEnvironment -DataRoot $smokeDataDir -DryRun:$true -SyncHash $sync | Out-Null
    }
    else {
        Initialize-OptiKitEnvironment -DryRun:$DryRunMode -SyncHash $sync | Out-Null
    }

    $configs = Get-OptiKitCatalogConfigs
    $hardware = Get-OptiKitHardware
    $window = [Windows.Markup.XamlReader]::Parse($configs.ThemeXaml)
    $ui = Initialize-OptiKitUi -Window $window -Configs $configs -Hardware $hardware

    Write-OptimizerLog -Level INFO -Message ("OptiKit iniciado ({0})" -f $hardware.Summary)
    if ($script:OptiKit.DryRun) {
        Write-OptimizerLog -Level DRYRUN -Message 'Modo de simulação (-DryRun) ativo: nenhuma alteração real será feita no sistema.'
    }

    if (-not [string]::IsNullOrWhiteSpace($InitialPreset)) {
        Select-OptiKitPreset -Ui $ui -PresetKey $InitialPreset
    }

    # Carregar Startup Items
    $refreshStartupFn = {
        $items = Get-OptiKitStartupItems
        $ui.GridStartupItems.ItemsSource = @($items)
    }.GetNewClosure()
    & $refreshStartupFn

    # Eventos da Aba de Manutenção
    $ui.BtnRefreshStartup.Add_Click($refreshStartupFn)

    $ui.BtnEnableStartup.Add_Click({
        $sel = $ui.GridStartupItems.SelectedItem
        if (-not $sel) {
            Write-OptimizerLog -Level WARN -Message 'Selecione um item na tabela de inicialização primeiro.'
            return
        }
        if (Set-OptiKitStartupItemState -Item $sel -Enabled $true) {
            & $refreshStartupFn
        }
    }.GetNewClosure())

    $ui.BtnDisableStartup.Add_Click({
        $sel = $ui.GridStartupItems.SelectedItem
        if (-not $sel) {
            Write-OptimizerLog -Level WARN -Message 'Selecione um item na tabela de inicialização primeiro.'
            return
        }
        if (Set-OptiKitStartupItemState -Item $sel -Enabled $false) {
            & $refreshStartupFn
        }
    }.GetNewClosure())

    $ui.BtnOpenBackupsDir.Add_Click({
        if (Test-Path -LiteralPath $script:OptiKit.DataRoot) {
            Start-Process -FilePath 'explorer.exe' -ArgumentList $script:OptiKit.DataRoot
        }
    }.GetNewClosure())

    $ui.BtnExportProfile.Add_Click({
        $tweaks = New-Object 'System.Collections.Generic.List[string]'
        foreach ($tid in $ui.SelectedTweakIds) {
            [void]$tweaks.Add($tid)
        }
        $gameOpts = New-Object 'System.Collections.Generic.List[string]'
        foreach ($gid in $ui.GameOptCheckboxes.Keys) {
            if ($ui.GameOptCheckboxes[$gid].CheckBox.IsChecked -eq $true) { [void]$gameOpts.Add($gid) }
        }
        $apps = New-Object 'System.Collections.Generic.List[string]'
        foreach ($aid in $ui.AppCheckboxes.Keys) {
            if ($ui.AppCheckboxes[$aid].CheckBox.IsChecked -eq $true) { [void]$apps.Add($aid) }
        }

        $presetKey = ''
        if ($ui.CmbPresets -and $ui.CmbPresets.SelectedItem -and $null -ne $ui.CmbPresets.SelectedItem.Tag) {
            $presetKey = [string]$ui.CmbPresets.SelectedItem.Tag
        }

        $optiKitProfile = ConvertTo-OptiKitProfile -Tweaks $tweaks.ToArray() -GameOptimizations $gameOpts.ToArray() -Apps $apps.ToArray() -Preset $presetKey
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Filter = 'Perfil OptiKit (*.json)|*.json'
        $dlg.FileName = 'optikit-profile.json'
        $dlg.Title = 'Exportar perfil de seleção do OptiKit'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $json = $optiKitProfile | ConvertTo-Json -Depth 5
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($dlg.FileName, $json, $utf8NoBom)
            Write-OptimizerLog -Level OK -Message ("Perfil exportado: {0}" -f $dlg.FileName)
        }
    }.GetNewClosure())

    $ui.BtnImportProfile.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = 'Perfil OptiKit (*.json)|*.json|Todos os arquivos (*.*)|*.*'
        $dlg.Title = 'Importar perfil do OptiKit'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                $selection = ConvertFrom-OptiKitProfile -Path $dlg.FileName -Configs $configs
                Set-OptiKitSelectionFromProfile -Ui $ui -Selection $selection
            }
            catch {
                Write-OptimizerLog -Level ERROR -Message ("Falha ao importar perfil: {0}" -f $_.Exception.Message)
                [void][System.Windows.MessageBox]::Show($window, $_.Exception.Message, 'Importar perfil', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            }
        }
    }.GetNewClosure())

    $ui.BtnExportReport.Add_Click({
        Start-OptiKitWorkerTask -SyncHash $sync -WorkerScript {
            $diagnostics = @(Get-OptiKitHardwareDiagnostics)
            $path = Export-OptiKitReport -Diagnostics $diagnostics -Counts $SyncHash.SessionCounts
            if ($path -and (Test-Path -LiteralPath $path)) {
                Start-Process -FilePath $path
            }
        }
    }.GetNewClosure())

    $ui.BtnUndoAll.Add_Click({
        $state = Read-OptiKitStateFile
        if ($state.Count -eq 0) {
            Write-OptimizerLog -Level WARN -Message 'Nenhum estado capturado para reverter.'
            return
        }

        $confirm = [System.Windows.MessageBox]::Show($window, ("Reverter {0}?`r`n`r`nIsso desfaz ajustes, otimizações de jogos, plano de energia, USB, DirectX, DNS e Windows Update registrados pelo OptiKit." -f (Format-OptiKitCount -Count $state.Count -Singular 'alteração registrada' -Plural 'alterações registradas')), 'Reverter tudo', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) {
            return
        }

        Start-OptiKitWorkerTask -SyncHash $sync -Arguments @{
            TweaksConfig       = $configs.WinTweaks
            GameProfilesConfig = $configs.GameProfiles
            AppsConfig         = $configs.Apps
            PresetsConfig      = $configs.Presets
        } -WorkerScript {
            $allConfigs = @{
                WinTweaks    = $WorkerArgs.TweaksConfig
                GameProfiles = $WorkerArgs.GameProfilesConfig
                Apps         = $WorkerArgs.AppsConfig
                Presets      = $WorkerArgs.PresetsConfig
            }
            [void](Invoke-OptiKitRevertAll -Configs $allConfigs)
            $SyncHash.PendingStateReport = Get-AllTweaksState -TweaksConfig $WorkerArgs.TweaksConfig -GameProfilesConfig $WorkerArgs.GameProfilesConfig
        }
    }.GetNewClosure())

    if ($ui.BadgeUpdate) {
        $ui.BadgeUpdate.Add_MouseLeftButtonUp({
            Start-Process -FilePath ("https://github.com/{0}/releases/latest" -f $script:OptiKitRepo)
        }.GetNewClosure())
    }

    $ui.BtnResetNetwork.Add_Click({
        Start-OptiKitWorkerTask -SyncHash $sync -WorkerScript {
            Invoke-NetworkReset
        }
    }.GetNewClosure())

    $ui.BtnClearTemp.Add_Click({
        Start-OptiKitWorkerTask -SyncHash $sync -WorkerScript {
            Clear-TemporaryFiles
        }
    }.GetNewClosure())

    $ui.BtnRunSfcDism.Add_Click({
        Start-OptiKitWorkerTask -SyncHash $sync -WorkerScript {
            Invoke-SystemIntegrityRepair
        }
    }.GetNewClosure())

    $ui.BtnRebootUefi.Add_Click({
        $confirm = [System.Windows.MessageBox]::Show($window, "Reiniciar agora para a BIOS/UEFI?`r`n`r`nSalve seu trabalho. O OptiKit não altera configurações da BIOS; a tela de firmware abre na próxima inicialização.", 'Reiniciar para a BIOS (OptiKit)', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

        Start-OptiKitWorkerTask -SyncHash $sync -WorkerScript {
            Restart-OptiKitToUefi
        }
    }.GetNewClosure())

    $ui.BtnCancelMaintenance.Add_Click({
        $sync.CancelRequest = $true
        $script:OptiKit.CancelRequest = $true
        Write-OptimizerLog -Level WARN -Message 'Solicitação de cancelamento enviada ao processo em execução...'
    }.GetNewClosure())

    $ui.BtnApplyDoh.Add_Click({
        if (-not $ui.DohSupported) { return }
        $selected = $ui.CmbDohProvider.SelectedItem
        if (-not $selected) {
            Write-OptimizerLog -Level WARN -Message 'Selecione um provedor de DoH primeiro.'
            return
        }
        $providerKey = [string]$selected.Tag
        $providerName = [string]$selected.Content
        $confirm = [System.Windows.MessageBox]::Show($window, ("Aplicar DNS over HTTPS com {0}?`r`n`r`nO DNS dos adaptadores físicos ativos será alterado. O DNS atual fica salvo para reverter." -f $providerName), 'Aplicar DNS over HTTPS', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

        Start-OptiKitWorkerTask -SyncHash $sync -Arguments @{ ProviderKey = $providerKey } -WorkerScript {
            Set-OptiKitDohProvider -ProviderKey $WorkerArgs.ProviderKey
        }
    }.GetNewClosure())

    $ui.BtnUndoDoh.Add_Click({
        if (-not $ui.DohSupported) { return }
        $confirm = [System.Windows.MessageBox]::Show($window, 'Restaurar o DNS original dos adaptadores e remover os templates DoH aplicados pelo OptiKit?', 'Reverter DNS over HTTPS', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

        Start-OptiKitWorkerTask -SyncHash $sync -WorkerScript {
            Restore-OptiKitDns
        }
    }.GetNewClosure())

    $ui.BtnWingetUpgrade.Add_Click({
        $confirm = [System.Windows.MessageBox]::Show($window, "Atualizar todos os aplicativos gerenciados pelo winget?`r`n`r`nPode demorar, e alguns aplicativos podem pedir reinicialização.", 'Atualizar aplicativos', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

        Start-OptiKitWorkerTask -SyncHash $sync -WorkerScript {
            Invoke-OptiKitWingetUpgrade -All | Out-Null
        }
    }.GetNewClosure())

    $ui.BtnAdvancedCleanup.Add_Click({
        $confirm = [System.Windows.MessageBox]::Show($window, "Limpeza avançada:`r`n`r`n• Cache do Windows Update`r`n• Cache do Delivery Optimization`r`n• Lixeira`r`n• Prefetch`r`n• Component Store via DISM`r`n`r`nPode demorar vários minutos. Continuar?", 'Limpeza avançada', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

        Start-OptiKitWorkerTask -SyncHash $sync -WorkerScript {
            Invoke-AdvancedCleanup
        }
    }.GetNewClosure())

    # Verificação de Estado
    $triggerStateCheck = {
        Start-OptiKitWorkerTask -SyncHash $sync -Arguments @{
            TweaksConfig       = $configs.WinTweaks
            GameProfilesConfig = $configs.GameProfiles
            SkipUpdateCheck    = $IsSmokeTest
        } -WorkerScript {
            Write-OptimizerLog -Level INFO -Message 'Verificando estado atual dos ajustes na máquina...'
            $SyncHash.PendingStateReport = Get-AllTweaksState -TweaksConfig $WorkerArgs.TweaksConfig -GameProfilesConfig $WorkerArgs.GameProfilesConfig
            if (-not $WorkerArgs.SkipUpdateCheck) {
                $SyncHash.PendingUpdateInfo = Test-OptiKitUpdateAvailable
            }
            Write-OptimizerLog -Level OK -Message 'Verificação de estado concluída.'
        }
    }.GetNewClosure()

    $ui.BtnRefreshState.Add_Click($triggerStateCheck)

    $triggerDiagnostics = {
        Start-OptiKitWorkerTask -SyncHash $sync -WorkerScript {
            Write-OptimizerLog -Level INFO -Message 'Executando diagnóstico de hardware (somente leitura)...'
            $SyncHash.PendingDiagnosticsReport = Get-OptiKitHardwareDiagnostics
            Write-OptimizerLog -Level OK -Message 'Diagnóstico de hardware concluído.'
        }
    }.GetNewClosure()

    $ui.BtnRefreshDiagnostics.Add_Click($triggerDiagnostics)

    # Benchmark de jogos (PresentMon)
    $benchmarkState = [hashtable]::Synchronized(@{
        Running         = $false
        Process         = $null
        ProcessName     = ''
        CsvPath         = ''
        JsonPath        = ''
        StartedAt       = $null
        DurationSeconds = 30
    })
    $benchmarkTimer = New-Object System.Windows.Threading.DispatcherTimer
    $benchmarkTimer.Interval = [TimeSpan]::FromMilliseconds(500)

    $resetBenchmarkControls = {
        $ui.BtnStartBenchmark.IsEnabled = (-not $sync.IsBusy)
        $ui.BtnStopBenchmark.IsEnabled = $false
        $ui.CmbBenchmarkProcess.IsEnabled = $true
        $ui.BtnRefreshBenchmarkProcesses.IsEnabled = $true
    }.GetNewClosure()

    $finishBenchmark = {
        if (-not $benchmarkState.Running) { return }
        $benchmarkState.Running = $false
        $benchmarkTimer.Stop()
        try {
            if ($benchmarkState.Process -and -not $benchmarkState.Process.HasExited) {
                [void]$benchmarkState.Process.WaitForExit(5000)
            }
            $previous = Get-OptiKitLatestBenchmark -ExcludePath $benchmarkState.JsonPath -ProcessName $benchmarkState.ProcessName
            $result = Get-OptiKitBenchmarkResult -CsvPath $benchmarkState.CsvPath
            $rows = Get-OptiKitBenchmarkComparisonRows -Current $result -Previous $previous
            Export-OptiKitBenchmarkResult -Result $result -ProcessName $benchmarkState.ProcessName -CsvPath $benchmarkState.CsvPath -OutputPath $benchmarkState.JsonPath | Out-Null
            $ui.GridBenchmarkResults.ItemsSource = $rows
            $ui.TxtBenchmarkStatus.Text = ("Captura concluída: {0} frames em {1:N1} s." -f $result.Frames, $result.DurationSeconds)
            Write-OptimizerLog -Level OK -Message ("Benchmark concluído: {0} FPS médio, {1:N1} FPS 1% low." -f $result.AverageFps, $result.OnePercentLow)
        }
        catch {
            $ui.TxtBenchmarkStatus.Text = ("Falha no benchmark: {0}" -f $_.Exception.Message)
            Write-OptimizerLog -Level WARN -Message ("Falha no benchmark: {0}" -f $_.Exception.Message)
        }
        finally {
            if ($benchmarkState.Process) {
                try { $benchmarkState.Process.Dispose() } catch { Write-Verbose $_.Exception.Message }
            }
            $benchmarkState.Process = $null
            $benchmarkState.ProcessName = ''
            $benchmarkState.CsvPath = ''
            $benchmarkState.JsonPath = ''
            $benchmarkState.StartedAt = $null
            & $resetBenchmarkControls
        }
    }.GetNewClosure()

    $benchmarkTimer.Add_Tick({
        if (-not $benchmarkState.Running) {
            $benchmarkTimer.Stop()
            return
        }
        try {
            $elapsed = ((Get-Date) - [datetime]$benchmarkState.StartedAt).TotalSeconds
            $remaining = [Math]::Max(0, [double]$benchmarkState.DurationSeconds - $elapsed)
            $ui.TxtBenchmarkStatus.Text = ("Capturando... {0:N0}s restantes" -f $remaining)

            if ($benchmarkState.Process -and $benchmarkState.Process.HasExited) {
                & $finishBenchmark
                return
            }
            if ($elapsed -gt ([double]$benchmarkState.DurationSeconds + 15)) {
                Stop-OptiKitBenchmark -Process $benchmarkState.Process
                $benchmarkState.Running = $false
                $benchmarkTimer.Stop()
                $ui.TxtBenchmarkStatus.Text = 'Tempo esgotado ao aguardar o PresentMon.'
                Write-OptimizerLog -Level WARN -Message 'Tempo esgotado ao aguardar o PresentMon.'
                if ($benchmarkState.Process) {
                    try { $benchmarkState.Process.Dispose() } catch { Write-Verbose $_.Exception.Message }
                }
                $benchmarkState.Process = $null
                $benchmarkState.ProcessName = ''
                $benchmarkState.CsvPath = ''
                $benchmarkState.JsonPath = ''
                $benchmarkState.StartedAt = $null
                & $resetBenchmarkControls
            }
        }
        catch {
            $benchmarkState.Running = $false
            $benchmarkTimer.Stop()
            $ui.TxtBenchmarkStatus.Text = ("Falha no benchmark: {0}" -f $_.Exception.Message)
            Write-OptimizerLog -Level WARN -Message ("Falha no benchmark: {0}" -f $_.Exception.Message)
            if ($benchmarkState.Process) {
                Stop-OptiKitBenchmark -Process $benchmarkState.Process
                try { $benchmarkState.Process.Dispose() } catch { Write-Verbose $_.Exception.Message }
            }
            $benchmarkState.Process = $null
            $benchmarkState.ProcessName = ''
            $benchmarkState.CsvPath = ''
            $benchmarkState.JsonPath = ''
            $benchmarkState.StartedAt = $null
            & $resetBenchmarkControls
        }
    }.GetNewClosure())

    $refreshBenchmarkProcesses = {
        if (-not $ui.CmbBenchmarkProcess) { return }
        try {
            $ui.CmbBenchmarkProcess.Items.Clear()
            $names = @(Get-Process -ErrorAction Stop |
                Where-Object { $_.MainWindowHandle -ne 0 -and $_.ProcessName -notin @('OptiKit', 'powershell', 'pwsh', 'explorer') } |
                Select-Object -ExpandProperty ProcessName |
                Sort-Object -Unique)
            foreach ($name in $names) {
                [void]$ui.CmbBenchmarkProcess.Items.Add($name)
            }
            if ($names.Count -gt 0) {
                $ui.CmbBenchmarkProcess.SelectedIndex = 0
                $ui.TxtBenchmarkStatus.Text = 'Selecione um jogo em execução e inicie a captura.'
            }
            else {
                $ui.TxtBenchmarkStatus.Text = 'Abra um jogo antes de capturar.'
            }
        }
        catch {
            $ui.TxtBenchmarkStatus.Text = ("Falha ao listar processos: {0}" -f $_.Exception.Message)
            Write-OptimizerLog -Level WARN -Message ("Falha ao listar processos para benchmark: {0}" -f $_.Exception.Message)
        }
    }.GetNewClosure()

    $ui.BtnRefreshBenchmarkProcesses.Add_Click($refreshBenchmarkProcesses)
    $ui.BtnStartBenchmark.Add_Click({
        if ($sync.IsBusy -or $benchmarkState.Running) { return }
        $name = [string]$ui.CmbBenchmarkProcess.Text
        if ([string]::IsNullOrWhiteSpace($name)) {
            $ui.TxtBenchmarkStatus.Text = 'Selecione ou digite o processo do jogo.'
            return
        }

        $ui.TxtBenchmarkStatus.Text = 'Preparando PresentMon...'
        try {
            $benchmark = Start-OptiKitBenchmark -ProcessName $name -DurationSeconds 30
        }
        catch {
            $ui.TxtBenchmarkStatus.Text = ("Falha ao iniciar: {0}" -f $_.Exception.Message)
            Write-OptimizerLog -Level WARN -Message ("Falha ao iniciar benchmark: {0}" -f $_.Exception.Message)
            return
        }

        $benchmarkState.Process = $benchmark.Process
        $benchmarkState.ProcessName = $benchmark.ProcessName
        $benchmarkState.CsvPath = $benchmark.CsvPath
        $benchmarkState.JsonPath = $benchmark.JsonPath
        $benchmarkState.StartedAt = $benchmark.StartedAt
        $benchmarkState.DurationSeconds = $benchmark.DurationSeconds
        $benchmarkState.Running = $true
        $ui.GridBenchmarkResults.ItemsSource = $null
        $ui.BtnStartBenchmark.IsEnabled = $false
        $ui.BtnStopBenchmark.IsEnabled = $true
        $ui.CmbBenchmarkProcess.IsEnabled = $false
        $ui.BtnRefreshBenchmarkProcesses.IsEnabled = $false
        $benchmarkTimer.Start()
    }.GetNewClosure())

    $ui.BtnStopBenchmark.Add_Click({
        if (-not $benchmarkState.Running) { return }
        $ui.TxtBenchmarkStatus.Text = 'Finalizando captura...'
        Stop-OptiKitBenchmark -Process $benchmarkState.Process
    }.GetNewClosure())

    & $refreshBenchmarkProcesses

    $ui.BtnViewApplied.Add_Click({
        Show-AppliedChangesDialog -Ui $ui
    }.GetNewClosure())

    # Aplicar / Reverter Selecionados
    $executeBatchAction = {
        param([string]$ActionMode)

        $selectedTweaks = New-Object 'System.Collections.Generic.List[hashtable]'
        foreach ($tid in $ui.SelectedTweakIds) {
            $definition = if ($ui.TweakDefinitionMap) { $ui.TweakDefinitionMap[$tid] } else { $null }
            if ($definition) {
                [void]$selectedTweaks.Add(@{ Id = $tid; Config = $definition.Config })
            }
        }

        $selectedGameOpts = New-Object 'System.Collections.Generic.List[hashtable]'
        foreach ($gid in $ui.GameOptCheckboxes.Keys) {
            $entry = $ui.GameOptCheckboxes[$gid]
            if ($entry.CheckBox.IsChecked -eq $true) {
                $customExe = if ($ui.CustomGameExePaths.ContainsKey($entry.ProfileKey)) { $ui.CustomGameExePaths[$entry.ProfileKey] } else { $null }
                [void]$selectedGameOpts.Add(@{
                    Id         = $gid
                    Profile    = $entry.Profile
                    Config     = $entry.Config
                    CustomExe  = $customExe
                })
            }
        }

        $selectedApps = New-Object 'System.Collections.Generic.List[hashtable]'
        if ($ActionMode -eq 'Apply') {
            foreach ($aid in $ui.AppCheckboxes.Keys) {
                $entry = $ui.AppCheckboxes[$aid]
                if ($entry.CheckBox.IsChecked -eq $true) {
                    [void]$selectedApps.Add(@{ Id = $aid; Config = $entry.Config })
                }
            }
        }

        $totalOps = $selectedTweaks.Count + $selectedGameOpts.Count + $selectedApps.Count
        if ($totalOps -eq 0) {
            Write-OptimizerLog -Level WARN -Message 'Nenhum item marcado. Selecione ao menos um ajuste ou aplicativo antes de continuar.'
            return
        }

        $rebootItems = @($selectedTweaks | Where-Object { $_.Config.requiresReboot } | ForEach-Object { $_.Config.title })
        $modeTitle = if ($ActionMode -eq 'Apply') { 'Aplicar selecionados' } else { 'Reverter selecionados' }

        if (-not $IsSmokeTest) {
            $summaryText = "Operação: $modeTitle`r`n• Ajustes do Windows: $($selectedTweaks.Count)`r`n• Otimizações de jogos: $($selectedGameOpts.Count)"
            if ($ActionMode -eq 'Apply') {
                $summaryText += "`r`n• Aplicativos (winget): $($selectedApps.Count)"
            }
            if ($rebootItems.Count -gt 0) {
                $summaryText += "`r`n`r`nExigem reinicialização:`r`n- " + ($rebootItems -join "`r`n- ")
            }
            if ($script:OptiKit -and $script:OptiKit.DryRun) {
                $summaryText += "`r`n`r`nModo simulação ativo: nada será gravado no Windows. Para aplicar de verdade, execute o win.ps1 sem -DryRun."
            }
            $summaryText += "`r`n`r`nDeseja prosseguir?"
            $confirm = [System.Windows.MessageBox]::Show($window, $summaryText, 'Confirmar', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
            if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) {
                return
            }
        }

        Start-OptiKitWorkerTask -SyncHash $sync -Arguments @{
            Mode               = $ActionMode
            Tweaks             = $selectedTweaks.ToArray()
            GameOpts           = $selectedGameOpts.ToArray()
            Apps               = $selectedApps.ToArray()
            AllTweaksConfig    = $configs.WinTweaks
            AllGamesConfig     = $configs.GameProfiles
        } -WorkerScript {
            $mode = $WorkerArgs.Mode
            $tweaks = @($WorkerArgs.Tweaks)
            $gameOpts = @($WorkerArgs.GameOpts)
            $apps = @($WorkerArgs.Apps)
            $total = [math]::Max(1, ($tweaks.Count + $gameOpts.Count + $apps.Count))
            $done = 0

            New-OptiKitBackupSession | Out-Null
            if ($mode -eq 'Apply' -and ($tweaks.Count -gt 0 -or $gameOpts.Count -gt 0)) {
                New-OptiKitRestorePoint -Description 'OptiKit - Antes de aplicar otimizações' | Out-Null
            }

            foreach ($tw in $tweaks) {
                try {
                    $ok = Invoke-Tweak -Id $tw.Id -Tweak $tw.Config -Mode $mode
                    if ($ok) {
                        $SyncHash.SessionCounts.Applied++
                    }
                    else {
                        $SyncHash.SessionCounts.Skipped++
                    }
                }
                catch {
                    $SyncHash.SessionCounts.Failed++
                    Write-OptimizerLog -Level WARN -Message ("Falha no tweak '{0}': {1}" -f $tw.Id, $_.Exception.Message)
                }
                $done++
                $SyncHash.Progress = [int](($done / $total) * 90)
            }

            foreach ($go in $gameOpts) {
                try {
                    $ok = Invoke-GameOptimization -ProfileConfig $go.Profile -Optimization $go.Config -Mode $mode -CustomExePath $go.CustomExe
                    if ($ok) {
                        $SyncHash.SessionCounts.Applied++
                    }
                    else {
                        $SyncHash.SessionCounts.Skipped++
                    }
                }
                catch {
                    $SyncHash.SessionCounts.Failed++
                    Write-OptimizerLog -Level WARN -Message ("Falha na otimização '{0}': {1}" -f $go.Id, $_.Exception.Message)
                }
                $done++
                $SyncHash.Progress = [int](($done / $total) * 90)
            }

            if ($mode -eq 'Apply') {
                foreach ($ap in $apps) {
                    try {
                        $ok = Install-OptiKitApp -AppKey $ap.Id -AppConfig $ap.Config
                        if ($ok) {
                            $SyncHash.SessionCounts.Applied++
                        }
                        else {
                            $SyncHash.SessionCounts.Failed++
                        }
                    }
                    catch {
                        $SyncHash.SessionCounts.Failed++
                        Write-OptimizerLog -Level WARN -Message ("Falha ao instalar '{0}': {1}" -f $ap.Id, $_.Exception.Message)
                    }
                    $done++
                    $SyncHash.Progress = [int](($done / $total) * 90)
                }
            }

            $SyncHash.PendingStateReport = Get-AllTweaksState -TweaksConfig $WorkerArgs.AllTweaksConfig -GameProfilesConfig $WorkerArgs.AllGamesConfig
            Write-OptimizerLog -Level OK -Message ("Processamento em lote ({0}) finalizado." -f $mode)
        }
    }.GetNewClosure()

    $ui.BtnApplySelected.Add_Click({ & $executeBatchAction 'Apply' }.GetNewClosure())
    $ui.BtnUndoSelected.Add_Click({ & $executeBatchAction 'Undo' }.GetNewClosure())

    # Timer de sincronização na UI Thread (100ms, sem risco de deadlock)
    $uiTimer = New-Object System.Windows.Threading.DispatcherTimer
    $uiTimer.Interval = [TimeSpan]::FromMilliseconds(100)
    $uiTimer.Add_Tick({
        $logItem = $null
        $appended = $false
        $lastLevel = $null
        while ($sync.LogQueue.TryDequeue([ref]$logItem)) {
            $ui.TxtConsoleOutput.AppendText($logItem.Formatted + [Environment]::NewLine)
            $appended = $true
            $lastLevel = [string]$logItem.Level
            if (($lastLevel -eq 'ERROR') -and $ui.LogPanel) {
                $ui.LogPanel.Visibility = 'Visible'
            }
        }
        if ($appended) {
            $ui.TxtConsoleOutput.ScrollToEnd()
        }
        if ($lastLevel) {
            $statusBrushKey = switch ($lastLevel) {
                'ERROR' { 'Brush.Danger' }
                'WARN' { 'Brush.Warning' }
                default { 'Brush.Text.Secondary' }
            }
            $ui.TxtStatusMessage.Foreground = $window.FindResource($statusBrushKey)
        }

        $ui.MainProgressBar.Value = [double]$sync.Progress
        $ui.TxtStatusMessage.Text = [string]$sync.StatusText

        $busy = [bool]$sync.IsBusy
        $ui.MainProgressBar.Visibility = if ($busy) { 'Visible' } else { 'Hidden' }
        $hasSelection = ([int]$ui.SelectionCount -gt 0)
        $ui.BtnApplySelected.IsEnabled = ((-not $busy) -and $hasSelection)
        $ui.BtnUndoSelected.IsEnabled = ((-not $busy) -and $hasSelection)
        $ui.BtnUndoAll.IsEnabled = (-not $busy)
        $ui.BtnResetNetwork.IsEnabled = (-not $busy)
        $ui.BtnRunSfcDism.IsEnabled = (-not $busy)
        $ui.BtnRebootUefi.IsEnabled = (-not $busy)
        $ui.BtnClearTemp.IsEnabled = (-not $busy)
        $ui.BtnRefreshDiagnostics.IsEnabled = (-not $busy)
        $ui.BtnExportReport.IsEnabled = (-not $busy)
        $ui.CmbDohProvider.IsEnabled = ((-not $busy) -and $ui.DohSupported)
        $ui.BtnApplyDoh.IsEnabled = ((-not $busy) -and $ui.DohSupported)
        $ui.BtnUndoDoh.IsEnabled = ((-not $busy) -and $ui.DohSupported)
        $ui.BtnWingetUpgrade.IsEnabled = (-not $busy)
        $ui.BtnAdvancedCleanup.IsEnabled = (-not $busy)
        $ui.BtnCancelMaintenance.IsEnabled = $busy

        $benchmarkRunning = [bool]$benchmarkState.Running
        $ui.BtnStartBenchmark.IsEnabled = ((-not $busy) -and (-not $benchmarkRunning))
        $ui.BtnStopBenchmark.IsEnabled = $benchmarkRunning
        $ui.CmbBenchmarkProcess.IsEnabled = (-not $benchmarkRunning)
        $ui.BtnRefreshBenchmarkProcesses.IsEnabled = (-not $benchmarkRunning)

        if (-not $busy -and $sync.PendingDiagnosticsStart) {
            $sync.PendingDiagnosticsStart = $false
            & $triggerDiagnostics
        }

        if ($null -ne $sync.PendingStateReport) {
            $rep = $sync.PendingStateReport
            $sync.PendingStateReport = $null
            Update-OptiKitStateBadges -Ui $ui -StateReport $rep
        }

        if ($null -ne $sync.PendingDiagnosticsReport) {
            $diag = $sync.PendingDiagnosticsReport
            $sync.PendingDiagnosticsReport = $null
            Update-OptiKitDiagnosticsUi -Ui $ui -Items @($diag)
        }

        if ($null -ne $sync.PendingUpdateInfo) {
            $update = $sync.PendingUpdateInfo
            $sync.PendingUpdateInfo = $null
            if ($update -and $ui.BadgeUpdate) {
                $ui.TxtUpdateBadge.Text = ("Versão {0} disponível" -f $update.Version)
                $ui.BadgeUpdate.ToolTip = 'Clique para abrir a página de releases do OptiKit.'
                $ui.BadgeUpdate.Visibility = 'Visible'
            }
        }

        if (-not $busy -and $null -ne $sync.ActivePowerShell -and $sync.AsyncResult.IsCompleted) {
            try {
                $sync.ActivePowerShell.EndInvoke($sync.AsyncResult) | Out-Null
            }
            catch {
                Write-Verbose ("Erro ao encerrar worker PowerShell: {0}" -f $_.Exception.Message)
            }
            finally {
                $sync.ActivePowerShell.Dispose()
                $sync.ActiveRunspace.Close()
                $sync.ActiveRunspace.Dispose()
                $sync.ActivePowerShell = $null
                $sync.ActiveRunspace = $null
                $sync.AsyncResult = $null
            }
        }
    }.GetNewClosure())
    $uiTimer.Start()

    $smokeTimer = $null
    if ($IsSmokeTest) {
        $smokeTimer = New-Object System.Windows.Threading.DispatcherTimer
        $smokeTimer.Interval = [TimeSpan]::FromMilliseconds(1000)
        $smokeTimer.Add_Tick({
            if ($sync.IsBusy) { return }
            $smokeTimer.Stop()
            Select-OptiKitPreset -Ui $ui -PresetKey 'MinimoSeguro'
            Invoke-SearchFilter -Ui $ui -Query 'Mouse'
            Invoke-SearchFilter -Ui $ui -Query ''
            $window.Close()
        }.GetNewClosure())
    }

    $window.Add_ContentRendered({
        & $triggerStateCheck
        if (-not $IsSmokeTest) {
            $sync.PendingDiagnosticsStart = $true
        }
        if ($null -ne $smokeTimer) {
            $smokeTimer.Start()
        }
    }.GetNewClosure())

    $window.Add_Closed({
        $uiTimer.Stop()
        $benchmarkTimer.Stop()
        Stop-OptiKitBenchmark -Process $benchmarkState.Process
        if ($sync.ActivePowerShell) {
            try { $sync.ActivePowerShell.Dispose() } catch { Write-Verbose $_.Exception.Message }
        }
        if ($sync.ActiveRunspace) {
            try { $sync.ActiveRunspace.Dispose() } catch { Write-Verbose $_.Exception.Message }
        }
    }.GetNewClosure())

    [void]$window.ShowDialog()
}

if (-not $script:OptiKitSkipAutoStart) {
    $effDryRun = ([bool]$DryRun -or [bool]$OptiKitInitDryRun)
    $effSmoke = ([bool]$SmokeTest -or [bool]$OptiKitInitSmokeTest)
    $effNoElev = ([bool]$NoElevate -or [bool]$OptiKitInitNoElevate)
    $effRelaunched = ([bool]$Relaunched -or [bool]$OptiKitInitRelaunched)
    $effPreset = if (-not [string]::IsNullOrWhiteSpace($Preset)) { $Preset } else { [string]$OptiKitInitPreset }
    $effApply = ([bool]$Apply -or [bool]$OptiKitInitApply)
    $effSilent = ([bool]$Silent -or [bool]$OptiKitInitSilent)
    $effConfig = if (-not [string]::IsNullOrWhiteSpace($Config)) { $Config } else { [string]$OptiKitInitConfig }
    Start-OptiKitMain -DryRunMode:$effDryRun -InitialPreset $effPreset -IsSmokeTest:$effSmoke -SkipElevation:$effNoElev -IsRelaunched:$effRelaunched -ApplyMode:$effApply -SilentMode:$effSilent -ConfigPath $effConfig
}
