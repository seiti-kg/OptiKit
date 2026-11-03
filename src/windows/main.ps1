# Inicializador principal do redimo (Windows): UAC, STA, Runspace Worker assíncrono e ciclo de vida da GUI WPF

#region dev-only
[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$Preset,
    [switch]$SmokeTest,
    [switch]$NoElevate
)

$devRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'core\logger.ps1')
. (Join-Path $PSScriptRoot 'core\backup.ps1')
. (Join-Path $PSScriptRoot 'modules\hardware-utils.ps1')
. (Join-Path $PSScriptRoot 'modules\winget-engine.ps1')
. (Join-Path $PSScriptRoot 'modules\tweak-engine.ps1')
. (Join-Path $PSScriptRoot 'modules\game-engine.ps1')
. (Join-Path $PSScriptRoot 'modules\maintenance.ps1')
. (Join-Path $PSScriptRoot 'modules\startup-manager.ps1')
. (Join-Path $PSScriptRoot 'core\state-checker.ps1')
. (Join-Path $PSScriptRoot 'ui\ui-builder.ps1')
#endregion

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-RedimoRelaunch {
    param(
        [switch]$AsAdmin,
        [switch]$PassDryRun,
        [string]$PassPreset,
        [switch]$PassSmokeTest,
        [switch]$PassNoElevate
    )

    $tempScript = Join-Path $env:TEMP 'redimo_bootstrap.ps1'
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)

    if ($MyInvocation.PSCommandPath -and (Test-Path -LiteralPath $MyInvocation.PSCommandPath)) {
        $tempScript = $MyInvocation.PSCommandPath
    }
    else {
        $scriptBody = $MyInvocation.MyCommand.ScriptBlock.ToString()
        [System.IO.File]::WriteAllText($tempScript, $scriptBody, $utf8Bom)
    }

    $argList = New-Object 'System.Collections.Generic.List[string]'
    [void]$argList.Add('-NoProfile')
    [void]$argList.Add('-ExecutionPolicy')
    [void]$argList.Add('Bypass')
    [void]$argList.Add('-STA')
    [void]$argList.Add('-File')
    [void]$argList.Add(('"{0}"' -f $tempScript))

    if ($PassDryRun) { [void]$argList.Add('-DryRun') }
    if (-not [string]::IsNullOrWhiteSpace($PassPreset)) {
        [void]$argList.Add('-Preset')
        [void]$argList.Add(('"{0}"' -f $PassPreset))
    }
    if ($PassSmokeTest) { [void]$argList.Add('-SmokeTest') }
    if ($PassNoElevate) { [void]$argList.Add('-NoElevate') }

    $startParams = @{
        FilePath     = 'powershell.exe'
        ArgumentList = ($argList -join ' ')
        Wait         = $true
        PassThru     = $true
    }
    if ($AsAdmin) {
        $startParams['Verb'] = 'RunAs'
    }

    try {
        $proc = Start-Process @startParams
        exit $proc.ExitCode
    }
    catch {
        Write-Warning ("Elevação UAC cancelada ou falhou: {0}" -f $_.Exception.Message)
        exit 1
    }
}

function Get-RedimoCatalogConfigs {
    if ($script:EmbeddedAppsJson -and $script:EmbeddedWinTweaksJson -and $script:EmbeddedGameProfilesJson -and $script:EmbeddedPresetsJson) {
        return @{
            Apps         = $script:EmbeddedAppsJson | ConvertFrom-Json
            WinTweaks    = $script:EmbeddedWinTweaksJson | ConvertFrom-Json
            GameProfiles = $script:EmbeddedGameProfilesJson | ConvertFrom-Json
            Presets      = $script:EmbeddedPresetsJson | ConvertFrom-Json
            ThemeXaml    = $script:EmbeddedThemeXaml
        }
    }

    $baseDir = if ($devRoot) { $devRoot } else { Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent }
    return @{
        Apps         = [System.IO.File]::ReadAllText((Join-Path $baseDir 'config\apps.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        WinTweaks    = [System.IO.File]::ReadAllText((Join-Path $baseDir 'config\win-tweaks.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        GameProfiles = [System.IO.File]::ReadAllText((Join-Path $baseDir 'config\game-profiles.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        Presets      = [System.IO.File]::ReadAllText((Join-Path $baseDir 'config\presets.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        ThemeXaml    = [System.IO.File]::ReadAllText((Join-Path $baseDir 'src\windows\ui\theme.xaml'), [System.Text.Encoding]::UTF8)
    }
}

function Start-RedimoWorkerTask {
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
        'Initialize-RedimoEnvironment', 'Write-OptimizerLog', 'Invoke-Mutation',
        'New-RedimoBackupSession', 'ConvertTo-RegExePath', 'Export-RegistryKeyBackup',
        'Read-RedimoStateFile', 'Write-RedimoStateFile', 'Save-CapturedState',
        'Get-CapturedState', 'Remove-CapturedState', 'New-RedimoRestorePoint',
        'Get-RedimoHardware', 'Get-ActivePowerPlanGuid', 'Set-RedimoSmartPowerPlan',
        'Enable-RedimoUltimatePowerPlan', 'Restore-RedimoPowerPlan',
        'Test-RedimoSmartPowerPlan', 'Test-RedimoUltimatePowerPlan',
        'Disable-RedimoHibernation', 'Enable-RedimoHibernation',
        'Optimize-UsbPower', 'Restore-UsbPower', 'Test-UsbPowerOptimized',
        'Test-WingetAvailable', 'Install-WingetBootstrap', 'Install-RedimoApp',
        'Test-OneDriveKfmActive', 'Remove-RedimoOneDrive', 'Install-RedimoOneDrive', 'Test-RedimoOneDriveRemoved',
        'Test-AntiCheatGuardrail', 'Get-RegistryEntryState', 'Set-RegistryEntryValue',
        'Set-ServiceStartupState', 'Set-ScheduledTaskState', 'Invoke-AppxRemoval',
        'Invoke-TweakHelperScript', 'Invoke-Tweak',
        'Find-GameExecutable', 'Set-AppCompatFlags', 'Set-DirectXGpuPreference',
        'Optimize-NetworkAdapterGaming', 'Disable-RiotClientStartup', 'Clear-ShaderCache',
        'Invoke-GameOptimization', 'Test-GameOptimizationApplied',
        'Invoke-NetworkReset', 'Invoke-CancelableProcess', 'Invoke-SystemIntegrityRepair', 'Clear-TemporaryFiles',
        'Get-RedimoStartupItems', 'Set-RedimoStartupItemState',
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
    $runspace.SessionStateProxy.SetVariable('ParentRedimo', $script:Redimo)

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace

    $wrapper = {
        $script:Redimo = $ParentRedimo
        $script:ProtectedAppxPackages = @(
            'Microsoft.WindowsStore', 'Microsoft.StorePurchaseApp', 'Microsoft.WindowsCalculator',
            'Microsoft.ScreenSketch', 'Microsoft.XboxIdentityProvider', 'Microsoft.GamingServices',
            'Microsoft.DesktopAppInstaller', 'Microsoft.VCLibs.140.00', 'Microsoft.UI.Xaml.2.7', 'Microsoft.UI.Xaml.2.8'
        )
        $script:AllowedTweakScripts = @(
            'Set-RedimoSmartPowerPlan', 'Enable-RedimoUltimatePowerPlan', 'Restore-RedimoPowerPlan',
            'Disable-RedimoHibernation', 'Enable-RedimoHibernation', 'Optimize-UsbPower',
            'Restore-UsbPower', 'Remove-RedimoOneDrive', 'Install-RedimoOneDrive'
        )
        $script:AllowedGameActions = @(
            'Set-AppCompatFlags', 'Set-DirectXGpuPreference', 'Optimize-NetworkAdapterGaming',
            'Disable-RiotClientStartup', 'Clear-ShaderCache', 'Optimize-UsbPower'
        )
        $script:AllowedCheckScripts = @(
            'Test-RedimoSmartPowerPlan', 'Test-RedimoUltimatePowerPlan', 'Test-UsbPowerOptimized', 'Test-RedimoOneDriveRemoved'
        )

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

function Start-RedimoMain {
    [CmdletBinding()]
    param(
        [switch]$DryRunMode,
        [string]$InitialPreset,
        [switch]$IsSmokeTest,
        [switch]$SkipElevation
    )

    if (-not $DryRunMode -and -not $IsSmokeTest -and -not $SkipElevation -and (-not (Test-IsAdministrator))) {
        Invoke-RedimoRelaunch -AsAdmin -PassDryRun:$DryRunMode -PassPreset $InitialPreset -PassSmokeTest:$IsSmokeTest
        return
    }

    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        Invoke-RedimoRelaunch -PassDryRun:$DryRunMode -PassPreset $InitialPreset -PassSmokeTest:$IsSmokeTest -PassNoElevate:$SkipElevation
        return
    }

    $sync = [hashtable]::Synchronized(@{
        LogQueue             = New-Object 'System.Collections.Concurrent.ConcurrentQueue[psobject]'
        Progress             = 0
        StatusText           = 'Inicializando redimo...'
        IsBusy               = $false
        CancelRequest        = $false
        PendingStateReport   = $null
        PendingStartupItems  = $null
        ActivePowerShell     = $null
        ActiveRunspace       = $null
        AsyncResult          = $null
    })

    if ($IsSmokeTest) {
        $smokeDataDir = Join-Path $env:TEMP ("redimo_smoke_" + [Guid]::NewGuid().ToString('N'))
        Initialize-RedimoEnvironment -DataRoot $smokeDataDir -DryRun:$true -SyncHash $sync | Out-Null
    }
    else {
        Initialize-RedimoEnvironment -DryRun:$DryRunMode -SyncHash $sync | Out-Null
    }

    $configs = Get-RedimoCatalogConfigs
    $hardware = Get-RedimoHardware
    $window = [Windows.Markup.XamlReader]::Parse($configs.ThemeXaml)
    $ui = Initialize-RedimoUi -Window $window -Configs $configs -Hardware $hardware

    Write-OptimizerLog -Level INFO -Message ("redimo iniciado ({0})" -f $hardware.Summary)
    if ($script:Redimo.DryRun) {
        Write-OptimizerLog -Level DRYRUN -Message 'Modo de simulação (-DryRun) ativo: nenhuma alteração real será feita no sistema.'
    }

    if (-not [string]::IsNullOrWhiteSpace($InitialPreset)) {
        Select-RedimoPreset -Ui $ui -PresetKey $InitialPreset
    }

    # Carregar Startup Items
    $refreshStartupFn = {
        $items = Get-RedimoStartupItems
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
        if (Set-RedimoStartupItemState -Item $sel -Enabled $true) {
            & $refreshStartupFn
        }
    }.GetNewClosure())

    $ui.BtnDisableStartup.Add_Click({
        $sel = $ui.GridStartupItems.SelectedItem
        if (-not $sel) {
            Write-OptimizerLog -Level WARN -Message 'Selecione um item na tabela de inicialização primeiro.'
            return
        }
        if (Set-RedimoStartupItemState -Item $sel -Enabled $false) {
            & $refreshStartupFn
        }
    }.GetNewClosure())

    $ui.BtnOpenBackupsDir.Add_Click({
        if (Test-Path -LiteralPath $script:Redimo.DataRoot) {
            Start-Process -FilePath 'explorer.exe' -ArgumentList $script:Redimo.DataRoot
        }
    }.GetNewClosure())

    $ui.BtnResetNetwork.Add_Click({
        Start-RedimoWorkerTask -SyncHash $sync -WorkerScript {
            Invoke-NetworkReset
        }
    }.GetNewClosure())

    $ui.BtnClearTemp.Add_Click({
        Start-RedimoWorkerTask -SyncHash $sync -WorkerScript {
            Clear-TemporaryFiles
        }
    }.GetNewClosure())

    $ui.BtnRunSfcDism.Add_Click({
        Start-RedimoWorkerTask -SyncHash $sync -WorkerScript {
            Invoke-SystemIntegrityRepair
        }
    }.GetNewClosure())

    $ui.BtnCancelMaintenance.Add_Click({
        $sync.CancelRequest = $true
        $script:Redimo.CancelRequest = $true
        Write-OptimizerLog -Level WARN -Message 'Solicitação de cancelamento enviada ao processo em execução...'
    }.GetNewClosure())

    # Verificação de Estado
    $triggerStateCheck = {
        Start-RedimoWorkerTask -SyncHash $sync -Arguments @{
            TweaksConfig       = $configs.WinTweaks
            GameProfilesConfig = $configs.GameProfiles
        } -WorkerScript {
            Write-OptimizerLog -Level INFO -Message 'Verificando estado atual dos ajustes na máquina...'
            $SyncHash.PendingStateReport = Get-AllTweaksState -TweaksConfig $WorkerArgs.TweaksConfig -GameProfilesConfig $WorkerArgs.GameProfilesConfig
            Write-OptimizerLog -Level OK -Message 'Verificação de estado concluída.'
        }
    }.GetNewClosure()

    $ui.BtnRefreshState.Add_Click($triggerStateCheck)
    $ui.BtnViewApplied.Add_Click({
        Show-AppliedChangesDialog -Ui $ui
    }.GetNewClosure())

    # Aplicar / Reverter Selecionados
    $executeBatchAction = {
        param([string]$ActionMode)

        $selectedTweaks = New-Object 'System.Collections.Generic.List[hashtable]'
        foreach ($tid in $ui.TweakCheckboxes.Keys) {
            $entry = $ui.TweakCheckboxes[$tid]
            if ($entry.CheckBox.IsChecked -eq $true) {
                [void]$selectedTweaks.Add(@{ Id = $tid; Config = $entry.Config })
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
        $modeTitle = if ($ActionMode -eq 'Apply') { 'Aplicar Selecionados' } else { 'Reverter Selecionados (Undo)' }

        if (-not $IsSmokeTest) {
            $summaryText = "Operação: $modeTitle`r`n• Tweaks de Sistema: $($selectedTweaks.Count)`r`n• Otimizações de Jogos: $($selectedGameOpts.Count)"
            if ($ActionMode -eq 'Apply') {
                $summaryText += "`r`n• Aplicativos Winget: $($selectedApps.Count)"
            }
            if ($rebootItems.Count -gt 0) {
                $summaryText += "`r`n`r`n⚠️ Itens que exigem reinicialização:`r`n- " + ($rebootItems -join "`r`n- ")
            }
            if ($script:Redimo -and $script:Redimo.DryRun) {
                $summaryText += "`r`n`r`n⚠️ MODO DRY-RUN (SIMULAÇÃO) ATIVO:`r`nNenhuma alteração real será gravada no Windows. Para aplicar de verdade, execute o win.ps1 sem a flag -DryRun."
            }
            $summaryText += "`r`n`r`nDeseja prosseguir?"
            $confirm = [System.Windows.MessageBox]::Show($window, $summaryText, "Confirmar Execução (redimo)", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
            if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) {
                return
            }
        }

        Start-RedimoWorkerTask -SyncHash $sync -Arguments @{
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

            New-RedimoBackupSession | Out-Null
            if ($mode -eq 'Apply' -and ($tweaks.Count -gt 0 -or $gameOpts.Count -gt 0)) {
                New-RedimoRestorePoint -Description 'redimo - Antes de aplicar otimizações' | Out-Null
            }

            foreach ($tw in $tweaks) {
                try {
                    Invoke-Tweak -Id $tw.Id -Tweak $tw.Config -Mode $mode | Out-Null
                }
                catch {
                    Write-OptimizerLog -Level WARN -Message ("Falha no tweak '{0}': {1}" -f $tw.Id, $_.Exception.Message)
                }
                $done++
                $SyncHash.Progress = [int](($done / $total) * 90)
            }

            foreach ($go in $gameOpts) {
                try {
                    Invoke-GameOptimization -ProfileConfig $go.Profile -Optimization $go.Config -Mode $mode -CustomExePath $go.CustomExe | Out-Null
                }
                catch {
                    Write-OptimizerLog -Level WARN -Message ("Falha na otimização '{0}': {1}" -f $go.Id, $_.Exception.Message)
                }
                $done++
                $SyncHash.Progress = [int](($done / $total) * 90)
            }

            if ($mode -eq 'Apply') {
                foreach ($ap in $apps) {
                    try {
                        Install-RedimoApp -AppKey $ap.Id -AppConfig $ap.Config | Out-Null
                    }
                    catch {
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
        while ($sync.LogQueue.TryDequeue([ref]$logItem)) {
            $ui.TxtConsoleOutput.AppendText($logItem.Formatted + [Environment]::NewLine)
            $appended = $true
        }
        if ($appended) {
            $ui.TxtConsoleOutput.ScrollToEnd()
        }

        $ui.MainProgressBar.Value = [double]$sync.Progress
        $ui.TxtStatusMessage.Text = [string]$sync.StatusText

        $busy = [bool]$sync.IsBusy
        $ui.BtnApplySelected.IsEnabled = (-not $busy)
        $ui.BtnUndoSelected.IsEnabled = (-not $busy)
        $ui.BtnResetNetwork.IsEnabled = (-not $busy)
        $ui.BtnRunSfcDism.IsEnabled = (-not $busy)
        $ui.BtnClearTemp.IsEnabled = (-not $busy)
        $ui.BtnCancelMaintenance.IsEnabled = $busy

        if ($null -ne $sync.PendingStateReport) {
            $rep = $sync.PendingStateReport
            $sync.PendingStateReport = $null
            Update-RedimoStateBadges -Ui $ui -StateReport $rep
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
            Select-RedimoPreset -Ui $ui -PresetKey 'MinimoSeguro'
            Invoke-SearchFilter -Ui $ui -Query 'Mouse'
            Invoke-SearchFilter -Ui $ui -Query ''
            $window.Close()
        }.GetNewClosure())
    }

    $window.Add_ContentRendered({
        & $triggerStateCheck
        if ($null -ne $smokeTimer) {
            $smokeTimer.Start()
        }
    }.GetNewClosure())

    $window.Add_Closed({
        $uiTimer.Stop()
        if ($sync.ActivePowerShell) {
            try { $sync.ActivePowerShell.Dispose() } catch { Write-Verbose $_.Exception.Message }
        }
        if ($sync.ActiveRunspace) {
            try { $sync.ActiveRunspace.Dispose() } catch { Write-Verbose $_.Exception.Message }
        }
    }.GetNewClosure())

    [void]$window.ShowDialog()
}

if (-not $script:RedimoSkipAutoStart) {
    $effDryRun = ([bool]$DryRun -or [bool]$RedimoInitDryRun)
    $effSmoke = ([bool]$SmokeTest -or [bool]$RedimoInitSmokeTest)
    $effNoElev = ([bool]$NoElevate -or [bool]$RedimoInitNoElevate)
    $effPreset = if (-not [string]::IsNullOrWhiteSpace($Preset)) { $Preset } else { [string]$RedimoInitPreset }
    Start-RedimoMain -DryRunMode:$effDryRun -InitialPreset $effPreset -IsSmokeTest:$effSmoke -SkipElevation:$effNoElev
}
