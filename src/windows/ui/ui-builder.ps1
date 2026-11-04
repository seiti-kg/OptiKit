# Construtor dinâmico de controles WPF a partir dos catálogos JSON (Data-Driven UI Builder)

#region dev-only
if (-not (Get-Command Write-OptimizerLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\core\logger.ps1')
}
if (-not (Get-Command Find-GameExecutable -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\modules\game-engine.ps1')
}
if (-not (Get-Command Test-OptiKitTweakBlocked -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\modules\hardware-utils.ps1')
}
if (-not (Get-Command Test-OptiKitDohSupported -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\modules\network-engine.ps1')
}
#endregion

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

function ConvertFrom-HexBrush {
    param([Parameter(Mandatory = $true)][string]$Hex)
    $conv = New-Object System.Windows.Media.BrushConverter
    return [System.Windows.Media.Brush]$conv.ConvertFromString($Hex)
}

function New-OptiKitBadge {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [string]$BgHex = '#27272A',
        [string]$BorderHex = '#3F3F46',
        [string]$FgHex = '#E4E4E7'
    )

    $border = New-Object System.Windows.Controls.Border
    $border.Background = ConvertFrom-HexBrush $BgHex
    $border.BorderBrush = ConvertFrom-HexBrush $BorderHex
    $border.BorderThickness = New-Object System.Windows.Thickness(1)
    $border.CornerRadius = New-Object System.Windows.CornerRadius(4)
    $border.Padding = New-Object System.Windows.Thickness(5, 1, 5, 1)
    $border.Margin = New-Object System.Windows.Thickness(4, 0, 0, 0)
    $border.VerticalAlignment = 'Center'
    $border.HorizontalAlignment = 'Right'

    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Text
    $tb.Foreground = ConvertFrom-HexBrush $FgHex
    $tb.FontSize = 10.5
    $tb.FontWeight = 'SemiBold'
    $border.Child = $tb

    return $border
}

function Get-ImpactColors {
    param([string]$Impact)
    switch ($Impact) {
        'Alto'        { return @{ Bg = '#082F38'; Border = '#00E5FF'; Fg = '#00E5FF' } }
        'Médio'       { return @{ Bg = '#172554'; Border = '#3B82F6'; Fg = '#60A5FA' } }
        'Baixo'       { return @{ Bg = '#27272A'; Border = '#52525B'; Fg = '#A1A1AA' } }
        'Situacional' { return @{ Bg = '#3B2F0B'; Border = '#F59E0B'; Fg = '#FBBF24' } }
        default       { return @{ Bg = '#27272A'; Border = '#52525B'; Fg = '#D4D4D8' } }
    }
}

function Get-RiskColors {
    param([string]$Risk)
    switch ($Risk) {
        'Safe'     { return @{ Bg = '#052E16'; Border = '#10B981'; Fg = '#34D399' } }
        'Moderate' { return @{ Bg = '#3B2F0B'; Border = '#F59E0B'; Fg = '#FBBF24' } }
        'Advanced' { return @{ Bg = '#3B1219'; Border = '#FF4655'; Fg = '#FF6B78' } }
        default    { return @{ Bg = '#27272A'; Border = '#52525B'; Fg = '#D4D4D8' } }
    }
}

function Get-DiagnosticColors {
    param([string]$Status)

    switch ($Status) {
        'OK'    { return @{ Bg = '#052E16'; Border = '#10B981'; Fg = '#34D399' } }
        'Warn'  { return @{ Bg = '#3B2F0B'; Border = '#F59E0B'; Fg = '#FBBF24' } }
        'Error' { return @{ Bg = '#3B1219'; Border = '#FF4655'; Fg = '#FF6B78' } }
        'Info'  { return @{ Bg = '#082F38'; Border = '#00E5FF'; Fg = '#00E5FF' } }
        default { return @{ Bg = '#27272A'; Border = '#52525B'; Fg = '#A1A1AA' } }
    }
}

function Update-SelectionCounter {
    param([Parameter(Mandatory = $true)][hashtable]$Ui)

    $count = 0
    foreach ($entry in $Ui.AppCheckboxes.Values) {
        if ($entry.CheckBox.IsChecked -eq $true) { $count++ }
    }
    foreach ($entry in $Ui.TweakCheckboxes.Values) {
        if ($entry.CheckBox.IsChecked -eq $true) { $count++ }
    }
    foreach ($entry in $Ui.GameOptCheckboxes.Values) {
        if ($entry.CheckBox.IsChecked -eq $true) { $count++ }
    }

    if ($Ui.TxtSelectionCounter) {
        $Ui.TxtSelectionCounter.Text = ("{0} itens selecionados" -f $count)
    }
}

function Select-OptiKitPreset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [Parameter(Mandatory = $true)][string]$PresetKey
    )

    $Ui.SuppressConfirmDialog = $true
    try {
        foreach ($entry in $Ui.AppCheckboxes.Values) { $entry.CheckBox.IsChecked = $false }
        foreach ($entry in $Ui.TweakCheckboxes.Values) { $entry.CheckBox.IsChecked = $false }
        foreach ($entry in $Ui.GameOptCheckboxes.Values) { $entry.CheckBox.IsChecked = $false }

        if ([string]::IsNullOrWhiteSpace($PresetKey)) {
            Update-SelectionCounter -Ui $Ui
            return
        }

        $presetProp = $Ui.Configs.Presets.PSObject.Properties[$PresetKey]
        if (-not $presetProp) {
            Write-OptimizerLog -Level WARN -Message ("Preset '{0}' não encontrado em presets.json." -f $PresetKey)
            return
        }

        $preset = $presetProp.Value
        foreach ($tid in @($preset.tweaks)) {
            if ($Ui.TweakCheckboxes.ContainsKey($tid)) {
                $entry = $Ui.TweakCheckboxes[$tid]
                if ($entry.CheckBox.IsEnabled) {
                    $entry.CheckBox.IsChecked = $true
                }
                else {
                    Write-OptimizerLog -Level WARN -Message ("Tweak '{0}' ignorado no preset '{1}': {2}" -f $tid, $PresetKey, $entry.BlockReason)
                }
            }
        }
        foreach ($gid in @($preset.gameOptimizations)) {
            if ($Ui.GameOptCheckboxes.ContainsKey($gid)) {
                $Ui.GameOptCheckboxes[$gid].CheckBox.IsChecked = $true
            }
        }
        foreach ($aid in @($preset.apps)) {
            if ($Ui.AppCheckboxes.ContainsKey($aid)) {
                $Ui.AppCheckboxes[$aid].CheckBox.IsChecked = $true
            }
        }

        Update-SelectionCounter -Ui $Ui
        Write-OptimizerLog -Level INFO -Message ("Preset '{0}' selecionado: {1}" -f $preset.name, $preset.description)
    }
    finally {
        $Ui.SuppressConfirmDialog = $false
    }
}

function Set-OptiKitSelectionFromProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [Parameter(Mandatory = $true)][pscustomobject]$Selection
    )

    $Ui.SuppressConfirmDialog = $true
    try {
        if ($Ui.CmbPresets) {
            $Ui.CmbPresets.SelectedIndex = 0
            $Ui.SuppressConfirmDialog = $true
        }
        foreach ($entry in $Ui.AppCheckboxes.Values) { $entry.CheckBox.IsChecked = $false }
        foreach ($entry in $Ui.TweakCheckboxes.Values) { $entry.CheckBox.IsChecked = $false }
        foreach ($entry in $Ui.GameOptCheckboxes.Values) { $entry.CheckBox.IsChecked = $false }

        foreach ($tweakId in @($Selection.Tweaks)) {
            if (-not $Ui.TweakCheckboxes.ContainsKey($tweakId)) {
                Write-OptimizerLog -Level WARN -Message ("Tweak '{0}' do perfil não está disponível neste Windows." -f $tweakId)
                continue
            }
            $entry = $Ui.TweakCheckboxes[$tweakId]
            if ($entry.CheckBox.IsEnabled) {
                $entry.CheckBox.IsChecked = $true
            }
            else {
                Write-OptimizerLog -Level WARN -Message ("Tweak '{0}' ignorado ao importar perfil: {1}" -f $tweakId, $entry.BlockReason)
            }
        }

        foreach ($gameOptId in @($Selection.GameOptimizations)) {
            if ($Ui.GameOptCheckboxes.ContainsKey($gameOptId)) {
                $Ui.GameOptCheckboxes[$gameOptId].CheckBox.IsChecked = $true
            }
            else {
                Write-OptimizerLog -Level WARN -Message ("Otimização '{0}' do perfil não está disponível." -f $gameOptId)
            }
        }

        foreach ($appId in @($Selection.Apps)) {
            if ($Ui.AppCheckboxes.ContainsKey($appId)) {
                $Ui.AppCheckboxes[$appId].CheckBox.IsChecked = $true
            }
            else {
                Write-OptimizerLog -Level WARN -Message ("App '{0}' do perfil não está disponível." -f $appId)
            }
        }

        Update-SelectionCounter -Ui $Ui
        Write-OptimizerLog -Level OK -Message ("Perfil importado: {0} tweak(s), {1} otimização(ões), {2} app(s)." -f @($Selection.Tweaks).Count, @($Selection.GameOptimizations).Count, @($Selection.Apps).Count)
    }
    finally {
        $Ui.SuppressConfirmDialog = $false
    }
}

function Update-OptiKitStateBadges {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [Parameter(Mandatory = $true)][pscustomobject]$StateReport
    )

    $Ui.LastStateReport = $StateReport

    if ($StateReport.Tweaks) {
        foreach ($tid in $StateReport.Tweaks.Keys) {
            if ($Ui.TweakCheckboxes.ContainsKey($tid)) {
                $st = $StateReport.Tweaks[$tid]
                $badge = $Ui.TweakCheckboxes[$tid].BadgeApplied
                if ($st -eq 'Applied') {
                    $badge.Visibility = 'Visible'
                }
                else {
                    $badge.Visibility = 'Collapsed'
                }
            }
        }
    }

    if ($StateReport.GameOpts) {
        foreach ($gid in $StateReport.GameOpts.Keys) {
            if ($Ui.GameOptCheckboxes.ContainsKey($gid)) {
                $isApp = [bool]$StateReport.GameOpts[$gid]
                $badge = $Ui.GameOptCheckboxes[$gid].BadgeApplied
                $badge.Visibility = if ($isApp) { 'Visible' } else { 'Collapsed' }
            }
        }
    }
}

function Update-OptiKitDiagnosticsUi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [Parameter(Mandatory = $true)][array]$Items
    )

    if (-not $Ui.DiagnosticsHost) {
        return
    }
    $Ui.DiagnosticsHost.Children.Clear()

    $ok = @($Items | Where-Object { $_.Status -eq 'OK' }).Count
    $warn = @($Items | Where-Object { $_.Status -eq 'Warn' }).Count
    $err = @($Items | Where-Object { $_.Status -eq 'Error' }).Count
    $info = @($Items | Where-Object { $_.Status -in @('Info', 'Unknown') }).Count

    if ($Ui.TxtDiagnosticsSummary) {
        $Ui.TxtDiagnosticsSummary.Text = ("{0} ok | {1} avisos | {2} erros | {3} info/desconhecido" -f $ok, $warn, $err, $info)
    }

    foreach ($item in $Items) {
        $colors = Get-DiagnosticColors -Status $item.Status
        $statusLabel = switch ($item.Status) {
            'OK'    { 'OK' }
            'Warn'  { 'Aviso' }
            'Error' { 'Erro' }
            'Info'  { 'Info' }
            default { 'Desconhecido' }
        }

        $card = New-Object System.Windows.Controls.Border
        $card.Background = ConvertFrom-HexBrush '#1E1E1E'
        $card.BorderBrush = ConvertFrom-HexBrush $colors.Border
        $card.BorderThickness = New-Object System.Windows.Thickness(1)
        $card.CornerRadius = New-Object System.Windows.CornerRadius(5)
        $card.Padding = New-Object System.Windows.Thickness(10, 7, 10, 7)
        $card.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)

        $stack = New-Object System.Windows.Controls.StackPanel
        $stack.Orientation = 'Vertical'

        $header = New-Object System.Windows.Controls.DockPanel
        $header.LastChildFill = $false

        $title = New-Object System.Windows.Controls.TextBlock
        $title.Text = $item.Title
        $title.FontSize = 13
        $title.FontWeight = 'SemiBold'
        $title.Foreground = ConvertFrom-HexBrush '#F3F4F6'
        $title.VerticalAlignment = 'Center'
        [System.Windows.Controls.DockPanel]::SetDock($title, 'Left')
        [void]$header.Children.Add($title)
        [void]$header.Children.Add((New-OptiKitBadge -Text $statusLabel -BgHex $colors.Bg -BorderHex $colors.Border -FgHex $colors.Fg))
        [void]$stack.Children.Add($header)

        $summary = New-Object System.Windows.Controls.TextBlock
        $summary.Text = [string]$item.Summary
        $summary.Foreground = ConvertFrom-HexBrush '#D4D4D8'
        $summary.FontSize = 12
        $summary.TextWrapping = 'Wrap'
        $summary.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
        [void]$stack.Children.Add($summary)

        if (-not [string]::IsNullOrWhiteSpace([string]$item.Detail)) {
            $detail = New-Object System.Windows.Controls.TextBlock
            $detail.Text = [string]$item.Detail
            $detail.Foreground = ConvertFrom-HexBrush '#9CA3AF'
            $detail.FontSize = 11
            $detail.TextWrapping = 'Wrap'
            $detail.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
            [void]$stack.Children.Add($detail)
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$item.ActionText)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$item.ActionUrl)) {
                $link = New-Object System.Windows.Documents.Hyperlink
                $run = New-Object System.Windows.Documents.Run
                $run.Text = ("→ {0}" -f $item.ActionText)
                $link.Inlines.Add($run)
                $link.Foreground = ConvertFrom-HexBrush $colors.Fg
                $link.NavigateUri = [Uri]$item.ActionUrl
                $link.Add_RequestNavigate({
                    param($linkSender, $navigateArgs)
                    try {
                        Start-Process -FilePath $navigateArgs.Uri.AbsoluteUri
                    }
                    catch {
                        Write-Verbose $_.Exception.Message
                    }
                    $navigateArgs.Handled = $true
                }.GetNewClosure())

                $actionBlock = New-Object System.Windows.Controls.TextBlock
                $actionBlock.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
                $actionBlock.Inlines.Add($link)
                [void]$stack.Children.Add($actionBlock)
            }
            else {
                $action = New-Object System.Windows.Controls.TextBlock
                $action.Text = ("→ {0}" -f $item.ActionText)
                $action.Foreground = ConvertFrom-HexBrush $colors.Fg
                $action.FontSize = 11.5
                $action.TextWrapping = 'Wrap'
                $action.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
                [void]$stack.Children.Add($action)
            }
        }

        $card.Child = $stack
        [void]$Ui.DiagnosticsHost.Children.Add($card)
    }
}

function Invoke-SearchFilter {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [AllowEmptyString()][string]$Query
    )

    $q = if ($Query) { $Query.Trim().ToLowerInvariant() } else { '' }

    foreach ($coll in @($Ui.AppCheckboxes.Values, $Ui.TweakCheckboxes.Values, $Ui.GameOptCheckboxes.Values)) {
        foreach ($entry in $coll) {
            if ([string]::IsNullOrEmpty($q) -or $entry.SearchText.Contains($q)) {
                $entry.Card.Visibility = 'Visible'
            }
            else {
                $entry.Card.Visibility = 'Collapsed'
            }
        }
    }
}

function Initialize-OptiKitUi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Windows.Window]$Window,
        [Parameter(Mandatory = $true)][hashtable]$Configs,
        [Parameter(Mandatory = $true)][pscustomobject]$Hardware
    )

    $ui = @{
        Window                = $Window
        Configs               = $Configs
        Hardware              = $Hardware
        AppCheckboxes         = @{}
        TweakCheckboxes       = @{}
        GameOptCheckboxes     = @{}
        CustomGameExePaths    = @{}
        SuppressConfirmDialog = $false
        LastStateReport       = $null
    }

    $controlNames = @(
        'BadgeDryRun', 'BadgeUpdate', 'TxtUpdateBadge', 'TxtHardwareSummary', 'TxtSearchBox', 'BtnClearSearch',
        'MainTabControl', 'AppsCategoriesHost', 'BtnUncheckAllApps',
        'TweaksCategoriesHost', 'BtnRefreshState', 'BtnUncheckAllTweaks',
        'GameProfilesHost',
        'BtnRefreshDiagnostics', 'TxtDiagnosticsSummary', 'DiagnosticsHost',
        'BtnResetNetwork', 'BtnRunSfcDism', 'BtnCancelMaintenance', 'BtnClearTemp', 'BtnOpenBackupsDir',
        'BtnExportProfile', 'BtnImportProfile', 'BtnExportReport',
        'CmbDohProvider', 'BtnApplyDoh', 'BtnUndoDoh', 'BtnWingetUpgrade', 'BtnAdvancedCleanup',
        'GridStartupItems', 'BtnEnableStartup', 'BtnDisableStartup', 'BtnRefreshStartup',
        'CmbPresets', 'BtnClearSelection', 'TxtSelectionCounter',
        'BtnViewApplied', 'BtnUndoSelected', 'BtnUndoAll', 'BtnApplySelected',
        'MainProgressBar', 'TxtStatusMessage', 'TxtConsoleOutput'
    )
    foreach ($name in $controlNames) {
        $ui[$name] = $Window.FindName($name)
    }

    $ui.DohSupported = Test-OptiKitDohSupported -Hardware $Hardware
    if ($ui.CmbDohProvider) {
        foreach ($provider in Get-OptiKitDohProviders) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = $provider.Name
            $item.Tag = $provider.Key
            [void]$ui.CmbDohProvider.Items.Add($item)
        }
        if ($ui.CmbDohProvider.Items.Count -gt 0) {
            $ui.CmbDohProvider.SelectedIndex = 0
        }
        if (-not $ui.DohSupported) {
            $ui.CmbDohProvider.IsEnabled = $false
            $ui.CmbDohProvider.ToolTip = 'DNS over HTTPS nativo requer Windows 11 (build 22000+).'
        }
    }
    if (-not $ui.DohSupported) {
        if ($ui.BtnApplyDoh) {
            $ui.BtnApplyDoh.IsEnabled = $false
            $ui.BtnApplyDoh.ToolTip = 'DNS over HTTPS nativo requer Windows 11 (build 22000+).'
        }
        if ($ui.BtnUndoDoh) {
            $ui.BtnUndoDoh.IsEnabled = $false
            $ui.BtnUndoDoh.ToolTip = 'DNS over HTTPS nativo requer Windows 11 (build 22000+).'
        }
    }

    if ($script:OptiKit -and $script:OptiKit.DryRun -and $ui.BadgeDryRun) {
        $ui.BadgeDryRun.Visibility = 'Visible'
    }
    if ($ui.TxtHardwareSummary -and $Hardware.Summary) {
        $ui.TxtHardwareSummary.Text = $Hardware.Summary
    }

    # 1. Construir Aba de Apps (Grade compacta de 4 colunas)
    $appCategoryOrder = @(
        'Navegadores',
        'Comunicação',
        'Jogos & Launchers',
        'Runtimes & Utilitários',
        'Desenvolvimento'
    )
    $appProps = @($Configs.Apps.PSObject.Properties)

    foreach ($catName in $appCategoryOrder) {
        $catItems = $appProps | Where-Object { $_.Value.category -eq $catName }
        if (-not $catItems -or @($catItems).Count -eq 0) { continue }

        $catHeader = New-Object System.Windows.Controls.TextBlock
        $catHeader.Text = $catName
        $catHeader.FontSize = 13.5
        $catHeader.FontWeight = 'Bold'
        $catHeader.Foreground = ConvertFrom-HexBrush '#00E5FF'
        $catHeader.Margin = New-Object System.Windows.Thickness(2, 6, 0, 4)
        [void]$ui.AppsCategoriesHost.Children.Add($catHeader)

        $grid = New-Object System.Windows.Controls.Primitives.UniformGrid
        $grid.Columns = 4

        foreach ($ap in $catItems) {
            $appKey = $ap.Name
            $appVal = $ap.Value

            $card = New-Object System.Windows.Controls.Border
            $card.Background = ConvertFrom-HexBrush '#1E1E1E'
            $card.BorderBrush = ConvertFrom-HexBrush '#2D2D32'
            $card.BorderThickness = New-Object System.Windows.Thickness(1)
            $card.CornerRadius = New-Object System.Windows.CornerRadius(5)
            $card.Padding = New-Object System.Windows.Thickness(8, 5, 8, 5)
            $card.Margin = New-Object System.Windows.Thickness(0, 0, 6, 5)
            $card.VerticalAlignment = 'Top'
            $card.ToolTip = ("{0}`r`nWinget ID: {1}`r`n`r`n{2}" -f $appVal.name, $appVal.winget, $appVal.description)

            $sp = New-Object System.Windows.Controls.StackPanel
            $sp.Orientation = 'Vertical'

            $cbLabel = New-Object System.Windows.Controls.TextBlock
            $cbLabel.Text = $appVal.name
            $cbLabel.Foreground = ConvertFrom-HexBrush '#F3F4F6'
            $cbLabel.FontWeight = 'SemiBold'
            $cbLabel.FontSize = 12.5
            $cbLabel.TextTrimming = 'CharacterEllipsis'

            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = $cbLabel
            $cb.VerticalContentAlignment = 'Center'
            $cb.Tag = $appKey
            $cb.Add_Checked({ Update-SelectionCounter -Ui $ui }.GetNewClosure())
            $cb.Add_Unchecked({ Update-SelectionCounter -Ui $ui }.GetNewClosure())

            $descTb = New-Object System.Windows.Controls.TextBlock
            $descTb.Text = $appVal.description
            $descTb.Foreground = ConvertFrom-HexBrush '#9CA3AF'
            $descTb.FontSize = 11
            $descTb.TextTrimming = 'CharacterEllipsis'
            $descTb.TextWrapping = 'NoWrap'
            $descTb.Margin = New-Object System.Windows.Thickness(20, 1, 0, 0)

            [void]$sp.Children.Add($cb)
            [void]$sp.Children.Add($descTb)
            $card.Child = $sp
            [void]$grid.Children.Add($card)

            $ui.AppCheckboxes[$appKey] = @{
                CheckBox   = $cb
                Card       = $card
                Config     = $appVal
                SearchText = ("{0} {1} {2} {3}" -f $appVal.name, $appVal.winget, $appVal.category, $appVal.description).ToLowerInvariant()
            }
        }

        [void]$ui.AppsCategoriesHost.Children.Add($grid)
    }

    # 2. Construir Aba de Tweaks (Grade compacta de 2 colunas)
    $tweakCategoryOrder = @(
        'Desempenho & Energia',
        'Privacidade & Telemetria',
        'Windows Update',
        'Interface & Windows 11',
        'Remoção de Bloatware (Appx)',
        'Avançado'
    )
    $osTag = if ($Hardware.IsWin11) { 'Win11' } else { 'Win10' }
    $tweakProps = @($Configs.WinTweaks.PSObject.Properties)

    foreach ($catName in $tweakCategoryOrder) {
        $catItems = $tweakProps | Where-Object {
            $t = $_.Value
            ($t.category -eq $catName) -and
            (@($t.osSupport) -contains $osTag) -and
            ($null -eq $t.minBuild -or $Hardware.OsBuild -ge [int]$t.minBuild)
        }
        if (-not $catItems -or @($catItems).Count -eq 0) { continue }

        $catHeader = New-Object System.Windows.Controls.TextBlock
        $catHeader.Text = $catName
        $catHeader.FontSize = 13.5
        $catHeader.FontWeight = 'Bold'
        $catHeader.Foreground = if ($catName -eq 'Avançado') { ConvertFrom-HexBrush '#FF4655' } else { ConvertFrom-HexBrush '#00E5FF' }
        $catHeader.Margin = New-Object System.Windows.Thickness(2, 6, 0, 4)
        [void]$ui.TweaksCategoriesHost.Children.Add($catHeader)

        $tweakGrid = New-Object System.Windows.Controls.Primitives.UniformGrid
        $tweakGrid.Columns = 2

        foreach ($tp in $catItems) {
            $tweakKey = $tp.Name
            $tweakVal = $tp.Value

            $card = New-Object System.Windows.Controls.Border
            $card.Background = ConvertFrom-HexBrush '#1E1E1E'
            $card.BorderBrush = if ($tweakVal.riskLevel -eq 'Advanced') { ConvertFrom-HexBrush '#7F1D1D' } else { ConvertFrom-HexBrush '#2D2D32' }
            $card.BorderThickness = New-Object System.Windows.Thickness(1)
            $card.CornerRadius = New-Object System.Windows.CornerRadius(5)
            $card.Padding = New-Object System.Windows.Thickness(9, 6, 9, 6)
            $card.Margin = New-Object System.Windows.Thickness(0, 0, 6, 5)
            $card.VerticalAlignment = 'Top'

            $rebootNote = if ($tweakVal.requiresReboot) { "`r`n⚠️ Requer reinicialização do sistema." } else { '' }
            $card.ToolTip = ("{0}`r`n`r`n📝 Descrição:`r`n{1}`r`n`r`n🔬 Justificativa Técnica (Anti-Placebo):`r`n{2}`r`n`r`nImpacto: {3} | Nível de Risco: {4}{5}" -f $tweakVal.title, $tweakVal.description, $tweakVal.rationale, $tweakVal.impact, $tweakVal.riskLevel, $rebootNote)

            $sp = New-Object System.Windows.Controls.StackPanel
            $sp.Orientation = 'Vertical'

            $headerRow = New-Object System.Windows.Controls.Grid
            $colLeft = New-Object System.Windows.Controls.ColumnDefinition
            $colLeft.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
            $colRight = New-Object System.Windows.Controls.ColumnDefinition
            $colRight.Width = [System.Windows.GridLength]::Auto
            [void]$headerRow.ColumnDefinitions.Add($colLeft)
            [void]$headerRow.ColumnDefinitions.Add($colRight)

            $cbTitle = New-Object System.Windows.Controls.TextBlock
            $cbTitle.Text = $tweakVal.title
            $cbTitle.Foreground = ConvertFrom-HexBrush '#F3F4F6'
            $cbTitle.FontWeight = 'SemiBold'
            $cbTitle.FontSize = 12.5
            $cbTitle.TextTrimming = 'CharacterEllipsis'

            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = $cbTitle
            $cb.VerticalContentAlignment = 'Center'
            $cb.Tag = $tweakKey

            $blockReason = Test-OptiKitTweakBlocked -Tweak $tweakVal -Hardware $Hardware
            if ($blockReason) {
                $cb.IsEnabled = $false
                $card.ToolTip += "`r`n`r`n⛔ BLOQUEADO NESTE HARDWARE:`r`n$blockReason"
            }

            $confirmText = $tweakVal.confirmMessage
            $cb.Add_Checked({
                if (-not [string]::IsNullOrWhiteSpace($confirmText) -and (-not $ui.SuppressConfirmDialog)) {
                    $ans = [System.Windows.MessageBox]::Show($ui.Window, $confirmText, 'Aviso de Segurança / Anti-Cheat (OptiKit)', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
                    if ($ans -ne [System.Windows.MessageBoxResult]::Yes) {
                        $this.IsChecked = $false
                        return
                    }
                }
                Update-SelectionCounter -Ui $ui
            }.GetNewClosure())
            $cb.Add_Unchecked({ Update-SelectionCounter -Ui $ui }.GetNewClosure())
            [System.Windows.Controls.Grid]::SetColumn($cb, 0)
            [void]$headerRow.Children.Add($cb)

            $badgesPanel = New-Object System.Windows.Controls.StackPanel
            $badgesPanel.Orientation = 'Horizontal'
            $badgesPanel.VerticalAlignment = 'Center'
            [System.Windows.Controls.Grid]::SetColumn($badgesPanel, 1)

            $badgeApplied = New-OptiKitBadge -Text '● Aplicado' -BgHex '#052E16' -BorderHex '#10B981' -FgHex '#34D399'
            $badgeApplied.Visibility = 'Collapsed'
            [void]$badgesPanel.Children.Add($badgeApplied)

            $impColors = Get-ImpactColors -Impact $tweakVal.impact
            $badgeImpact = New-OptiKitBadge -Text $tweakVal.impact -BgHex $impColors.Bg -BorderHex $impColors.Border -FgHex $impColors.Fg
            [void]$badgesPanel.Children.Add($badgeImpact)

            if ($tweakVal.riskLevel -ne 'Safe') {
                $riskColors = Get-RiskColors -Risk $tweakVal.riskLevel
                $badgeRisk = New-OptiKitBadge -Text $tweakVal.riskLevel -BgHex $riskColors.Bg -BorderHex $riskColors.Border -FgHex $riskColors.Fg
                [void]$badgesPanel.Children.Add($badgeRisk)
            }

            if ($blockReason) {
                [void]$badgesPanel.Children.Add((New-OptiKitBadge -Text 'Bloqueado' -BgHex '#3B1219' -BorderHex '#FF4655' -FgHex '#FF6B78'))
            }

            [void]$headerRow.Children.Add($badgesPanel)

            $descTb = New-Object System.Windows.Controls.TextBlock
            $descTb.Text = $tweakVal.description
            $descTb.Foreground = ConvertFrom-HexBrush '#9CA3AF'
            $descTb.FontSize = 11
            $descTb.TextTrimming = 'CharacterEllipsis'
            $descTb.TextWrapping = 'NoWrap'
            $descTb.Margin = New-Object System.Windows.Thickness(20, 2, 0, 0)

            [void]$sp.Children.Add($headerRow)
            [void]$sp.Children.Add($descTb)
            $card.Child = $sp
            [void]$tweakGrid.Children.Add($card)

            $ui.TweakCheckboxes[$tweakKey] = @{
                CheckBox     = $cb
                Card         = $card
                BadgeApplied = $badgeApplied
                Config       = $tweakVal
                BlockReason  = $blockReason
                SearchText   = ("{0} {1} {2} {3}" -f $tweakVal.title, $tweakVal.description, $tweakVal.rationale, $tweakVal.category).ToLowerInvariant()
            }
        }

        [void]$ui.TweaksCategoriesHost.Children.Add($tweakGrid)
    }

    # 3. Construir Aba de Perfis de Jogos
    foreach ($gp in $Configs.GameProfiles.PSObject.Properties) {
        $profKey = $gp.Name
        $prof = $gp.Value

        $profBorder = New-Object System.Windows.Controls.Border
        $profBorder.Background = ConvertFrom-HexBrush '#1E1E1E'
        $profBorder.BorderBrush = if ($prof.status -eq 'active') { ConvertFrom-HexBrush '#FF4655' } elseif ($prof.status -eq 'global') { ConvertFrom-HexBrush '#00E5FF' } else { ConvertFrom-HexBrush '#2D2D32' }
        $profBorder.BorderThickness = New-Object System.Windows.Thickness(1)
        $profBorder.CornerRadius = New-Object System.Windows.CornerRadius(7)
        $profBorder.Padding = New-Object System.Windows.Thickness(12, 9, 12, 9)
        $profBorder.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)

        $profStack = New-Object System.Windows.Controls.StackPanel
        $profStack.Orientation = 'Vertical'

        $titleDock = New-Object System.Windows.Controls.DockPanel
        $titleDock.LastChildFill = $false
        $titleTb = New-Object System.Windows.Controls.TextBlock
        $titleTb.Text = ("🎮 {0}" -f $prof.gameName)
        $titleTb.FontSize = 15
        $titleTb.FontWeight = 'Bold'
        $titleTb.Foreground = if ($prof.status -eq 'active') { ConvertFrom-HexBrush '#FF4655' } elseif ($prof.status -eq 'global') { ConvertFrom-HexBrush '#00E5FF' } else { ConvertFrom-HexBrush '#9CA3AF' }
        [System.Windows.Controls.DockPanel]::SetDock($titleTb, 'Left')
        [void]$titleDock.Children.Add($titleTb)

        $metaPanel = New-Object System.Windows.Controls.StackPanel
        $metaPanel.Orientation = 'Horizontal'
        [System.Windows.Controls.DockPanel]::SetDock($metaPanel, 'Right')

        [void]$metaPanel.Children.Add((New-OptiKitBadge -Text $prof.engine -BgHex '#121212' -BorderHex '#3F3F46' -FgHex '#D4D4D8'))
        [void]$metaPanel.Children.Add((New-OptiKitBadge -Text $prof.antiCheat -BgHex '#121212' -BorderHex '#3F3F46' -FgHex '#00E5FF'))

        if ($prof.status -eq 'comingSoon') {
            [void]$metaPanel.Children.Add((New-OptiKitBadge -Text 'EM BREVE' -BgHex '#3B2F0B' -BorderHex '#F59E0B' -FgHex '#FBBF24'))
        }
        [void]$titleDock.Children.Add($metaPanel)
        [void]$profStack.Children.Add($titleDock)

        $warnTb = New-Object System.Windows.Controls.TextBlock
        $warnTb.Text = $prof.warning
        $warnTb.Foreground = ConvertFrom-HexBrush '#D4D4D8'
        $warnTb.FontSize = 11.5
        $warnTb.TextWrapping = 'Wrap'
        $warnTb.Margin = New-Object System.Windows.Thickness(0, 3, 0, 6)
        [void]$profStack.Children.Add($warnTb)

        if ($prof.status -eq 'active') {
            $detectedExe = Find-GameExecutable -ProfileConfig $prof
            if ($detectedExe) {
                $ui.CustomGameExePaths[$profKey] = $detectedExe
            }

            $exeDock = New-Object System.Windows.Controls.DockPanel
            $exeDock.LastChildFill = $false
            $exeDock.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)

            $exeLabel = New-Object System.Windows.Controls.TextBlock
            $exeLabel.Text = if ($detectedExe) { "Executável detectado: $detectedExe" } else { "Executável não encontrado no caminho padrão (você pode selecioná-lo manualmente)." }
            $exeLabel.Foreground = if ($detectedExe) { ConvertFrom-HexBrush '#34D399' } else { ConvertFrom-HexBrush '#FBBF24' }
            $exeLabel.FontSize = 11.5
            $exeLabel.VerticalAlignment = 'Center'
            [System.Windows.Controls.DockPanel]::SetDock($exeLabel, 'Left')
            [void]$exeDock.Children.Add($exeLabel)

            $btnBrowse = New-Object System.Windows.Controls.Button
            $btnBrowse.Content = 'Selecionar .exe...'
            $btnBrowse.Style = $Window.FindResource('ActionButtonStyle')
            $btnBrowse.Padding = New-Object System.Windows.Thickness(10, 3, 10, 3)
            $btnBrowse.FontSize = 11.5
            [System.Windows.Controls.DockPanel]::SetDock($btnBrowse, 'Right')
            $btnBrowse.Add_Click({
                $dlg = New-Object System.Windows.Forms.OpenFileDialog
                $dlg.Filter = 'Executáveis (*.exe)|*.exe'
                $dlg.Title = ("Selecionar executável de {0}" -f $prof.gameName)
                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $ui.CustomGameExePaths[$profKey] = $dlg.FileName
                    $exeLabel.Text = ("Executável selecionado: {0}" -f $dlg.FileName)
                    $exeLabel.Foreground = ConvertFrom-HexBrush '#34D399'
                }
            }.GetNewClosure())
            [void]$exeDock.Children.Add($btnBrowse)
            [void]$profStack.Children.Add($exeDock)
        }

        $optGrid = New-Object System.Windows.Controls.Primitives.UniformGrid
        $optGrid.Columns = 2

        foreach ($opt in @($prof.optimizations)) {
            $optCard = New-Object System.Windows.Controls.Border
            $optCard.Background = ConvertFrom-HexBrush '#141417'
            $optCard.BorderBrush = ConvertFrom-HexBrush '#27272A'
            $optCard.BorderThickness = New-Object System.Windows.Thickness(1)
            $optCard.CornerRadius = New-Object System.Windows.CornerRadius(5)
            $optCard.Padding = New-Object System.Windows.Thickness(9, 6, 9, 6)
            $optCard.Margin = New-Object System.Windows.Thickness(0, 0, 6, 5)
            $optCard.VerticalAlignment = 'Top'
            $optCard.ToolTip = ("{0}`r`n`r`n🔬 Justificativa Técnica:`r`n{1}`r`n`r`nAction: {2} | Impacto: {3}" -f $opt.title, $opt.rationale, $opt.action, $opt.impact)

            $optSp = New-Object System.Windows.Controls.StackPanel
            $optSp.Orientation = 'Vertical'

            $optTop = New-Object System.Windows.Controls.Grid
            $c0 = New-Object System.Windows.Controls.ColumnDefinition
            $c0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
            $c1 = New-Object System.Windows.Controls.ColumnDefinition
            $c1.Width = [System.Windows.GridLength]::Auto
            [void]$optTop.ColumnDefinitions.Add($c0)
            [void]$optTop.ColumnDefinitions.Add($c1)

            $optCbTitle = New-Object System.Windows.Controls.TextBlock
            $optCbTitle.Text = $opt.title
            $optCbTitle.Foreground = ConvertFrom-HexBrush '#F3F4F6'
            $optCbTitle.FontWeight = 'SemiBold'
            $optCbTitle.FontSize = 12.5
            $optCbTitle.TextTrimming = 'CharacterEllipsis'

            $optCb = New-Object System.Windows.Controls.CheckBox
            $optCb.Content = $optCbTitle
            $optCb.VerticalContentAlignment = 'Center'
            $optCb.Tag = $opt.id
            $optCb.Add_Checked({ Update-SelectionCounter -Ui $ui }.GetNewClosure())
            $optCb.Add_Unchecked({ Update-SelectionCounter -Ui $ui }.GetNewClosure())
            [System.Windows.Controls.Grid]::SetColumn($optCb, 0)
            [void]$optTop.Children.Add($optCb)

            $optBadges = New-Object System.Windows.Controls.StackPanel
            $optBadges.Orientation = 'Horizontal'
            $optBadges.VerticalAlignment = 'Center'
            [System.Windows.Controls.Grid]::SetColumn($optBadges, 1)

            $optBadgeApp = New-OptiKitBadge -Text '● Aplicado' -BgHex '#052E16' -BorderHex '#10B981' -FgHex '#34D399'
            $optBadgeApp.Visibility = 'Collapsed'
            [void]$optBadges.Children.Add($optBadgeApp)

            $impCol = Get-ImpactColors -Impact $opt.impact
            [void]$optBadges.Children.Add((New-OptiKitBadge -Text $opt.impact -BgHex $impCol.Bg -BorderHex $impCol.Border -FgHex $impCol.Fg))
            [void]$optTop.Children.Add($optBadges)

            $optDesc = New-Object System.Windows.Controls.TextBlock
            $optDesc.Text = $opt.description
            $optDesc.Foreground = ConvertFrom-HexBrush '#9CA3AF'
            $optDesc.FontSize = 11
            $optDesc.TextTrimming = 'CharacterEllipsis'
            $optDesc.TextWrapping = 'NoWrap'
            $optDesc.Margin = New-Object System.Windows.Thickness(20, 2, 0, 0)

            [void]$optSp.Children.Add($optTop)
            [void]$optSp.Children.Add($optDesc)
            $optCard.Child = $optSp
            [void]$optGrid.Children.Add($optCard)

            $ui.GameOptCheckboxes[$opt.id] = @{
                CheckBox     = $optCb
                Card         = $optCard
                BadgeApplied = $optBadgeApp
                ProfileKey   = $profKey
                Profile      = $prof
                Config       = $opt
                SearchText   = ("{0} {1} {2} {3}" -f $prof.gameName, $opt.title, $opt.description, $opt.rationale).ToLowerInvariant()
            }
        }

        if (@($prof.optimizations).Count -gt 0) {
            [void]$profStack.Children.Add($optGrid)
        }
        $profBorder.Child = $profStack
        [void]$ui.GameProfilesHost.Children.Add($profBorder)
    }

    # 4. Popular ComboBox de Presets
    if ($ui.CmbPresets) {
        $placeholderItem = New-Object System.Windows.Controls.ComboBoxItem
        $placeholderItem.Content = 'Selecione um Preset...'
        $placeholderItem.Tag = ''
        [void]$ui.CmbPresets.Items.Add($placeholderItem)

        foreach ($prProp in $Configs.Presets.PSObject.Properties) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = $prProp.Value.name
            $item.Tag = $prProp.Name
            $item.ToolTip = $prProp.Value.description
            [void]$ui.CmbPresets.Items.Add($item)
        }
        $ui.CmbPresets.SelectedIndex = 0
        $ui.CmbPresets.Add_SelectionChanged({
            $sel = $ui.CmbPresets.SelectedItem
            if ($sel -and $null -ne $sel.Tag) {
                Select-OptiKitPreset -Ui $ui -PresetKey ([string]$sel.Tag)
            }
        }.GetNewClosure())
    }

    # 5. Eventos de Busca e Limpeza
    if ($ui.TxtSearchBox) {
        $ui.TxtSearchBox.Add_TextChanged({
            Invoke-SearchFilter -Ui $ui -Query $ui.TxtSearchBox.Text
        }.GetNewClosure())
    }
    if ($ui.BtnClearSearch) {
        $ui.BtnClearSearch.Add_Click({
            $ui.TxtSearchBox.Text = ''
        }.GetNewClosure())
    }
    if ($ui.BtnUncheckAllApps) {
        $ui.BtnUncheckAllApps.Add_Click({
            foreach ($e in $ui.AppCheckboxes.Values) { $e.CheckBox.IsChecked = $false }
            Update-SelectionCounter -Ui $ui
        }.GetNewClosure())
    }
    if ($ui.BtnUncheckAllTweaks) {
        $ui.BtnUncheckAllTweaks.Add_Click({
            foreach ($e in $ui.TweakCheckboxes.Values) { $e.CheckBox.IsChecked = $false }
            Update-SelectionCounter -Ui $ui
        }.GetNewClosure())
    }
    if ($ui.BtnClearSelection) {
        $ui.BtnClearSelection.Add_Click({
            $ui.CmbPresets.SelectedIndex = 0
            Select-OptiKitPreset -Ui $ui -PresetKey ''
        }.GetNewClosure())
    }

    return $ui
}

function Show-AppliedChangesDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui
    )

    $lines = New-Object 'System.Collections.Generic.List[string]'
    [void]$lines.Add('=== AJUSTES ATIVOS DETECTADOS NA MÁQUINA ===')

    $activeCount = 0
    foreach ($tid in $Ui.TweakCheckboxes.Keys) {
        $entry = $Ui.TweakCheckboxes[$tid]
        if ($entry.BadgeApplied.Visibility -eq 'Visible') {
            [void]$lines.Add(("• [Tweak] {0} ({1})" -f $entry.Config.title, $tid))
            $activeCount++
        }
    }
    foreach ($gid in $Ui.GameOptCheckboxes.Keys) {
        $entry = $Ui.GameOptCheckboxes[$gid]
        if ($entry.BadgeApplied.Visibility -eq 'Visible') {
            [void]$lines.Add(("• [Jogo] {0} ({1})" -f $entry.Config.title, $gid))
            $activeCount++
        }
    }

    if ($activeCount -eq 0) {
        [void]$lines.Add('Nenhum tweak do catálogo está marcado como aplicado no momento.')
    }

    [void]$lines.Add('')
    [void]$lines.Add('=== HISTÓRICO DE CAPTURA PARA REVERSÃO (state.json) ===')
    $stateMap = Read-OptiKitStateFile
    if ($stateMap.Count -eq 0) {
        [void]$lines.Add('Nenhuma captura registrada no state.json.')
    }
    else {
        foreach ($k in $stateMap.Keys) {
            $rec = $stateMap[$k]
            [void]$lines.Add(("• {0} (Sessão: {1})" -f $k, $rec.session))
        }
    }

    $msg = ($lines -join [Environment]::NewLine)
    [void][System.Windows.MessageBox]::Show($Ui.Window, $msg, 'Alterações Aplicadas no Sistema (OptiKit)', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
}
