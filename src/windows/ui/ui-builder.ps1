# Construtor dinâmico de controles WPF a partir dos catálogos JSON (Data-Driven UI Builder)

#region dev-only
if (-not (Get-Command Write-OptimizerLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\core\logger.ps1')
}
if (-not (Get-Command Find-GameExecutable -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\modules\game-engine.ps1')
}
#endregion

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

function ConvertFrom-HexBrush {
    param([Parameter(Mandatory = $true)][string]$Hex)
    $conv = New-Object System.Windows.Media.BrushConverter
    return [System.Windows.Media.Brush]$conv.ConvertFromString($Hex)
}

function New-RedimoBadge {
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
    $border.Padding = New-Object System.Windows.Thickness(6, 1, 6, 1)
    $border.Margin = New-Object System.Windows.Thickness(6, 0, 0, 0)
    $border.VerticalAlignment = 'Center'

    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Text
    $tb.Foreground = ConvertFrom-HexBrush $FgHex
    $tb.FontSize = 11
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

function Select-RedimoPreset {
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
                $Ui.TweakCheckboxes[$tid].CheckBox.IsChecked = $true
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

function Update-RedimoStateBadges {
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

function Initialize-RedimoUi {
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
        'BadgeDryRun', 'TxtHardwareSummary', 'TxtSearchBox', 'BtnClearSearch',
        'MainTabControl', 'AppsCategoriesHost', 'BtnUncheckAllApps',
        'TweaksCategoriesHost', 'BtnRefreshState', 'BtnUncheckAllTweaks',
        'GameProfilesHost',
        'BtnResetNetwork', 'BtnRunSfcDism', 'BtnCancelMaintenance', 'BtnClearTemp', 'BtnOpenBackupsDir',
        'GridStartupItems', 'BtnEnableStartup', 'BtnDisableStartup', 'BtnRefreshStartup',
        'CmbPresets', 'BtnClearSelection', 'TxtSelectionCounter',
        'BtnViewApplied', 'BtnUndoSelected', 'BtnApplySelected',
        'MainProgressBar', 'TxtStatusMessage', 'TxtConsoleOutput'
    )
    foreach ($name in $controlNames) {
        $ui[$name] = $Window.FindName($name)
    }

    if ($script:Redimo -and $script:Redimo.DryRun -and $ui.BadgeDryRun) {
        $ui.BadgeDryRun.Visibility = 'Visible'
    }
    if ($ui.TxtHardwareSummary -and $Hardware.Summary) {
        $ui.TxtHardwareSummary.Text = $Hardware.Summary
    }

    # 1. Construir Aba de Apps
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
        $catHeader.FontSize = 15
        $catHeader.FontWeight = 'Bold'
        $catHeader.Foreground = ConvertFrom-HexBrush '#00E5FF'
        $catHeader.Margin = New-Object System.Windows.Thickness(2, 10, 0, 6)
        [void]$ui.AppsCategoriesHost.Children.Add($catHeader)

        $grid = New-Object System.Windows.Controls.Primitives.UniformGrid
        $grid.Columns = 2

        foreach ($ap in $catItems) {
            $appKey = $ap.Name
            $appVal = $ap.Value

            $card = New-Object System.Windows.Controls.Border
            $card.Background = ConvertFrom-HexBrush '#1E1E1E'
            $card.BorderBrush = ConvertFrom-HexBrush '#2D2D32'
            $card.BorderThickness = New-Object System.Windows.Thickness(1)
            $card.CornerRadius = New-Object System.Windows.CornerRadius(6)
            $card.Padding = New-Object System.Windows.Thickness(10, 8, 10, 8)
            $card.Margin = New-Object System.Windows.Thickness(0, 0, 8, 8)
            $card.ToolTip = ("{0}`r`nWinget ID: {1}`r`n{2}" -f $appVal.name, $appVal.winget, $appVal.description)

            $sp = New-Object System.Windows.Controls.StackPanel
            $sp.Orientation = 'Vertical'

            $topRow = New-Object System.Windows.Controls.DockPanel
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = $appVal.name
            $cb.Foreground = ConvertFrom-HexBrush '#F3F4F6'
            $cb.FontWeight = 'SemiBold'
            $cb.FontSize = 13
            $cb.Tag = $appKey
            $cb.Add_Checked({ Update-SelectionCounter -Ui $ui }.GetNewClosure())
            $cb.Add_Unchecked({ Update-SelectionCounter -Ui $ui }.GetNewClosure())
            [void]$topRow.Children.Add($cb)

            $wgBadge = New-RedimoBadge -Text $appVal.winget -BgHex '#121212' -BorderHex '#2D2D32' -FgHex '#9CA3AF'
            [System.Windows.Controls.DockPanel]::SetDock($wgBadge, 'Right')
            [void]$topRow.Children.Add($wgBadge)

            $descTb = New-Object System.Windows.Controls.TextBlock
            $descTb.Text = $appVal.description
            $descTb.Foreground = ConvertFrom-HexBrush '#9CA3AF'
            $descTb.FontSize = 11.5
            $descTb.TextWrapping = 'Wrap'
            $descTb.Margin = New-Object System.Windows.Thickness(22, 3, 0, 0)

            [void]$sp.Children.Add($topRow)
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

    # 2. Construir Aba de Tweaks
    $tweakCategoryOrder = @(
        'Desempenho & Energia',
        'Privacidade & Telemetria',
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
        $catHeader.FontSize = 15
        $catHeader.FontWeight = 'Bold'
        $catHeader.Foreground = if ($catName -eq 'Avançado') { ConvertFrom-HexBrush '#FF4655' } else { ConvertFrom-HexBrush '#00E5FF' }
        $catHeader.Margin = New-Object System.Windows.Thickness(2, 10, 0, 6)
        [void]$ui.TweaksCategoriesHost.Children.Add($catHeader)

        foreach ($tp in $catItems) {
            $tweakKey = $tp.Name
            $tweakVal = $tp.Value

            $card = New-Object System.Windows.Controls.Border
            $card.Background = ConvertFrom-HexBrush '#1E1E1E'
            $card.BorderBrush = if ($tweakVal.riskLevel -eq 'Advanced') { ConvertFrom-HexBrush '#7F1D1D' } else { ConvertFrom-HexBrush '#2D2D32' }
            $card.BorderThickness = New-Object System.Windows.Thickness(1)
            $card.CornerRadius = New-Object System.Windows.CornerRadius(6)
            $card.Padding = New-Object System.Windows.Thickness(12, 9, 12, 9)
            $card.Margin = New-Object System.Windows.Thickness(0, 0, 0, 7)

            $rebootNote = if ($tweakVal.requiresReboot) { "`r`n⚠️ Requer reinicialização do sistema." } else { '' }
            $card.ToolTip = ("{0}`r`n`r`n🔬 Justificativa Técnica (Anti-Placebo):`r`n{1}`r`n`r`nImpacto: {2} | Nível de Risco: {3}{4}" -f $tweakVal.title, $tweakVal.rationale, $tweakVal.impact, $tweakVal.riskLevel, $rebootNote)

            $sp = New-Object System.Windows.Controls.StackPanel
            $sp.Orientation = 'Vertical'

            $headerRow = New-Object System.Windows.Controls.DockPanel
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = $tweakVal.title
            $cb.Foreground = ConvertFrom-HexBrush '#F3F4F6'
            $cb.FontWeight = 'SemiBold'
            $cb.FontSize = 13.5
            $cb.Tag = $tweakKey

            $confirmText = $tweakVal.confirmMessage
            $cb.Add_Checked({
                if (-not [string]::IsNullOrWhiteSpace($confirmText) -and (-not $ui.SuppressConfirmDialog)) {
                    $ans = [System.Windows.MessageBox]::Show($ui.Window, $confirmText, 'Aviso de Segurança / Anti-Cheat (redimo)', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
                    if ($ans -ne [System.Windows.MessageBoxResult]::Yes) {
                        $this.IsChecked = $false
                        return
                    }
                }
                Update-SelectionCounter -Ui $ui
            }.GetNewClosure())
            $cb.Add_Unchecked({ Update-SelectionCounter -Ui $ui }.GetNewClosure())
            [void]$headerRow.Children.Add($cb)

            $badgesPanel = New-Object System.Windows.Controls.StackPanel
            $badgesPanel.Orientation = 'Horizontal'
            [System.Windows.Controls.DockPanel]::SetDock($badgesPanel, 'Right')

            $badgeApplied = New-RedimoBadge -Text '● Aplicado' -BgHex '#052E16' -BorderHex '#10B981' -FgHex '#34D399'
            $badgeApplied.Visibility = 'Collapsed'
            [void]$badgesPanel.Children.Add($badgeApplied)

            $impColors = Get-ImpactColors -Impact $tweakVal.impact
            $badgeImpact = New-RedimoBadge -Text ("Impacto: {0}" -f $tweakVal.impact) -BgHex $impColors.Bg -BorderHex $impColors.Border -FgHex $impColors.Fg
            [void]$badgesPanel.Children.Add($badgeImpact)

            $riskColors = Get-RiskColors -Risk $tweakVal.riskLevel
            $badgeRisk = New-RedimoBadge -Text $tweakVal.riskLevel -BgHex $riskColors.Bg -BorderHex $riskColors.Border -FgHex $riskColors.Fg
            [void]$badgesPanel.Children.Add($badgeRisk)

            if ($tweakVal.requiresReboot) {
                $badgeReboot = New-RedimoBadge -Text 'Reboot' -BgHex '#27272A' -BorderHex '#52525B' -FgHex '#D4D4D8'
                [void]$badgesPanel.Children.Add($badgeReboot)
            }

            [void]$headerRow.Children.Add($badgesPanel)

            $descTb = New-Object System.Windows.Controls.TextBlock
            $descTb.Text = $tweakVal.description
            $descTb.Foreground = ConvertFrom-HexBrush '#9CA3AF'
            $descTb.FontSize = 12
            $descTb.TextWrapping = 'Wrap'
            $descTb.Margin = New-Object System.Windows.Thickness(22, 4, 0, 0)

            [void]$sp.Children.Add($headerRow)
            [void]$sp.Children.Add($descTb)
            $card.Child = $sp
            [void]$ui.TweaksCategoriesHost.Children.Add($card)

            $ui.TweakCheckboxes[$tweakKey] = @{
                CheckBox     = $cb
                Card         = $card
                BadgeApplied = $badgeApplied
                Config       = $tweakVal
                SearchText   = ("{0} {1} {2} {3}" -f $tweakVal.title, $tweakVal.description, $tweakVal.rationale, $tweakVal.category).ToLowerInvariant()
            }
        }
    }

    # 3. Construir Aba de Perfis de Jogos
    foreach ($gp in $Configs.GameProfiles.PSObject.Properties) {
        $profKey = $gp.Name
        $prof = $gp.Value

        $profBorder = New-Object System.Windows.Controls.Border
        $profBorder.Background = ConvertFrom-HexBrush '#1E1E1E'
        $profBorder.BorderBrush = if ($prof.status -eq 'active') { ConvertFrom-HexBrush '#FF4655' } elseif ($prof.status -eq 'global') { ConvertFrom-HexBrush '#00E5FF' } else { ConvertFrom-HexBrush '#2D2D32' }
        $profBorder.BorderThickness = New-Object System.Windows.Thickness(1)
        $profBorder.CornerRadius = New-Object System.Windows.CornerRadius(8)
        $profBorder.Padding = New-Object System.Windows.Thickness(14, 12, 14, 12)
        $profBorder.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)

        $profStack = New-Object System.Windows.Controls.StackPanel
        $profStack.Orientation = 'Vertical'

        $titleDock = New-Object System.Windows.Controls.DockPanel
        $titleTb = New-Object System.Windows.Controls.TextBlock
        $titleTb.Text = ("🎮 {0}" -f $prof.gameName)
        $titleTb.FontSize = 16
        $titleTb.FontWeight = 'Bold'
        $titleTb.Foreground = if ($prof.status -eq 'active') { ConvertFrom-HexBrush '#FF4655' } elseif ($prof.status -eq 'global') { ConvertFrom-HexBrush '#00E5FF' } else { ConvertFrom-HexBrush '#9CA3AF' }
        [void]$titleDock.Children.Add($titleTb)

        $metaPanel = New-Object System.Windows.Controls.StackPanel
        $metaPanel.Orientation = 'Horizontal'
        [System.Windows.Controls.DockPanel]::SetDock($metaPanel, 'Right')

        [void]$metaPanel.Children.Add((New-RedimoBadge -Text $prof.engine -BgHex '#121212' -BorderHex '#3F3F46' -FgHex '#D4D4D8'))
        [void]$metaPanel.Children.Add((New-RedimoBadge -Text $prof.antiCheat -BgHex '#121212' -BorderHex '#3F3F46' -FgHex '#00E5FF'))

        if ($prof.status -eq 'comingSoon') {
            [void]$metaPanel.Children.Add((New-RedimoBadge -Text 'EM BREVE' -BgHex '#3B2F0B' -BorderHex '#F59E0B' -FgHex '#FBBF24'))
        }
        [void]$titleDock.Children.Add($metaPanel)
        [void]$profStack.Children.Add($titleDock)

        $warnTb = New-Object System.Windows.Controls.TextBlock
        $warnTb.Text = $prof.warning
        $warnTb.Foreground = ConvertFrom-HexBrush '#D4D4D8'
        $warnTb.FontSize = 12
        $warnTb.TextWrapping = 'Wrap'
        $warnTb.Margin = New-Object System.Windows.Thickness(0, 4, 0, 8)
        [void]$profStack.Children.Add($warnTb)

        if ($prof.status -eq 'active') {
            $detectedExe = Find-GameExecutable -ProfileConfig $prof
            if ($detectedExe) {
                $ui.CustomGameExePaths[$profKey] = $detectedExe
            }

            $exeDock = New-Object System.Windows.Controls.DockPanel
            $exeDock.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)

            $exeLabel = New-Object System.Windows.Controls.TextBlock
            $exeLabel.Text = if ($detectedExe) { "Executável detectado: $detectedExe" } else { "Executável não encontrado no caminho padrão (você pode selecioná-lo manualmente)." }
            $exeLabel.Foreground = if ($detectedExe) { ConvertFrom-HexBrush '#34D399' } else { ConvertFrom-HexBrush '#FBBF24' }
            $exeLabel.FontSize = 12
            $exeLabel.VerticalAlignment = 'Center'
            [void]$exeDock.Children.Add($exeLabel)

            $btnBrowse = New-Object System.Windows.Controls.Button
            $btnBrowse.Content = 'Selecionar .exe...'
            $btnBrowse.Style = $Window.FindResource('ActionButtonStyle')
            $btnBrowse.Padding = New-Object System.Windows.Thickness(10, 4, 10, 4)
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

        foreach ($opt in @($prof.optimizations)) {
            $optCard = New-Object System.Windows.Controls.Border
            $optCard.Background = ConvertFrom-HexBrush '#141417'
            $optCard.BorderBrush = ConvertFrom-HexBrush '#27272A'
            $optCard.BorderThickness = New-Object System.Windows.Thickness(1)
            $optCard.CornerRadius = New-Object System.Windows.CornerRadius(5)
            $optCard.Padding = New-Object System.Windows.Thickness(10, 7, 10, 7)
            $optCard.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)
            $optCard.ToolTip = ("{0}`r`n`r`n🔬 Justificativa Técnica:`r`n{1}`r`n`r`nAction: {2} | Impacto: {3}" -f $opt.title, $opt.rationale, $opt.action, $opt.impact)

            $optSp = New-Object System.Windows.Controls.StackPanel
            $optSp.Orientation = 'Vertical'

            $optTop = New-Object System.Windows.Controls.DockPanel
            $optCb = New-Object System.Windows.Controls.CheckBox
            $optCb.Content = $opt.title
            $optCb.Foreground = ConvertFrom-HexBrush '#F3F4F6'
            $optCb.FontWeight = 'SemiBold'
            $optCb.FontSize = 13
            $optCb.Tag = $opt.id
            $optCb.Add_Checked({ Update-SelectionCounter -Ui $ui }.GetNewClosure())
            $optCb.Add_Unchecked({ Update-SelectionCounter -Ui $ui }.GetNewClosure())
            [void]$optTop.Children.Add($optCb)

            $optBadges = New-Object System.Windows.Controls.StackPanel
            $optBadges.Orientation = 'Horizontal'
            [System.Windows.Controls.DockPanel]::SetDock($optBadges, 'Right')

            $optBadgeApp = New-RedimoBadge -Text '● Aplicado' -BgHex '#052E16' -BorderHex '#10B981' -FgHex '#34D399'
            $optBadgeApp.Visibility = 'Collapsed'
            [void]$optBadges.Children.Add($optBadgeApp)

            $impCol = Get-ImpactColors -Impact $opt.impact
            [void]$optBadges.Children.Add((New-RedimoBadge -Text ("Impacto: {0}" -f $opt.impact) -BgHex $impCol.Bg -BorderHex $impCol.Border -FgHex $impCol.Fg))
            [void]$optTop.Children.Add($optBadges)

            $optDesc = New-Object System.Windows.Controls.TextBlock
            $optDesc.Text = $opt.description
            $optDesc.Foreground = ConvertFrom-HexBrush '#9CA3AF'
            $optDesc.FontSize = 11.5
            $optDesc.TextWrapping = 'Wrap'
            $optDesc.Margin = New-Object System.Windows.Thickness(22, 3, 0, 0)

            [void]$optSp.Children.Add($optTop)
            [void]$optSp.Children.Add($optDesc)
            $optCard.Child = $optSp
            [void]$profStack.Children.Add($optCard)

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
                Select-RedimoPreset -Ui $ui -PresetKey ([string]$sel.Tag)
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
            Select-RedimoPreset -Ui $ui -PresetKey ''
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
    $stateMap = Read-RedimoStateFile
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
    [void][System.Windows.MessageBox]::Show($Ui.Window, $msg, 'Alterações Aplicadas no Sistema (redimo)', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
}
