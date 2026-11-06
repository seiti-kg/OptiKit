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

function Get-OptiKitUiResource {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [Parameter(Mandatory = $true)][string]$Key
    )
    return $Ui.Window.FindResource($Key)
}

function Format-OptiKitCount {
    param(
        [Parameter(Mandatory = $true)][int]$Count,
        [Parameter(Mandatory = $true)][string]$Singular,
        [Parameter(Mandatory = $true)][string]$Plural
    )
    if ($Count -eq 1) { return ('1 {0}' -f $Singular) }
    return ('{0} {1}' -f $Count, $Plural)
}

function Format-OptiKitSelectionCount {
    param([int]$Count)
    if ($Count -le 0) { return 'Nenhum item selecionado' }
    return (Format-OptiKitCount -Count $Count -Singular 'item selecionado' -Plural 'itens selecionados')
}

function Format-OptiKitHardwareSummary {
    param([AllowEmptyString()][string]$Summary)
    return ((@($Summary -split '\s*\|\s*') | Where-Object { $_ }) -join [Environment]::NewLine)
}

function New-OptiKitText {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [AllowEmptyString()][string]$Text = '',
        [string]$Style = 'Text.Body',
        [ValidateSet('None', 'Wrap', 'Trim')][string]$Overflow = 'None',
        [string]$Brush
    )

    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Text
    $tb.Style = Get-OptiKitUiResource -Ui $Ui -Key $Style
    switch ($Overflow) {
        'Wrap' { $tb.TextWrapping = 'Wrap' }
        'Trim' {
            $tb.TextWrapping = 'NoWrap'
            $tb.TextTrimming = 'CharacterEllipsis'
        }
    }
    if ($Brush) {
        $tb.Foreground = Get-OptiKitUiResource -Ui $Ui -Key $Brush
    }
    return $tb
}

function New-OptiKitRun {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [Parameter(Mandatory = $true)][string]$Text,
        [string]$Brush
    )

    $run = New-Object System.Windows.Documents.Run($Text)
    if ($Brush) {
        $run.Foreground = Get-OptiKitUiResource -Ui $Ui -Key $Brush
    }
    return $run
}

function Get-OptiKitImpactLabel {
    param([string]$Impact)
    switch ($Impact) {
        'Alto' { return 'Impacto alto' }
        'Médio' { return 'Impacto médio' }
        'Baixo' { return 'Impacto baixo' }
        'Situacional' { return 'Situacional' }
        default { return [string]$Impact }
    }
}

function Get-OptiKitRiskLabel {
    param([string]$Risk)
    switch ($Risk) {
        'Moderate' { return @{ Text = 'Risco moderado'; Brush = 'Brush.Warning' } }
        'Advanced' { return @{ Text = 'Risco avançado'; Brush = 'Brush.Danger' } }
        default { return $null }
    }
}

function New-OptiKitToolTipContent {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [Parameter(Mandatory = $true)][string]$Title,
        [string]$Body,
        [string]$DetailLabel,
        [string]$Detail,
        [string]$Footer,
        [string]$Alert
    )

    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.MaxWidth = 416
    [void]$sp.Children.Add((New-OptiKitText -Ui $Ui -Text $Title -Style 'Text.BodyStrong' -Overflow Wrap))

    if (-not [string]::IsNullOrWhiteSpace($Body)) {
        $bodyTb = New-OptiKitText -Ui $Ui -Text $Body -Style 'Text.Caption' -Overflow Wrap
        $bodyTb.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
        [void]$sp.Children.Add($bodyTb)
    }
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        if (-not [string]::IsNullOrWhiteSpace($DetailLabel)) {
            $labelTb = New-OptiKitText -Ui $Ui -Text $DetailLabel -Style 'Text.Caption' -Brush 'Brush.Text.Primary'
            $labelTb.FontWeight = 'SemiBold'
            $labelTb.Margin = New-Object System.Windows.Thickness(0, 10, 0, 2)
            [void]$sp.Children.Add($labelTb)
        }
        [void]$sp.Children.Add((New-OptiKitText -Ui $Ui -Text $Detail -Style 'Text.Caption' -Overflow Wrap))
    }
    if (-not [string]::IsNullOrWhiteSpace($Footer)) {
        $footerTb = New-OptiKitText -Ui $Ui -Text $Footer -Style 'Text.Meta' -Overflow Wrap
        $footerTb.Margin = New-Object System.Windows.Thickness(0, 10, 0, 0)
        [void]$sp.Children.Add($footerTb)
    }
    if (-not [string]::IsNullOrWhiteSpace($Alert)) {
        $alertTb = New-OptiKitText -Ui $Ui -Text $Alert -Style 'Text.Caption' -Overflow Wrap -Brush 'Brush.Danger'
        $alertTb.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)
        [void]$sp.Children.Add($alertTb)
    }
    return $sp
}

function New-OptiKitItemRow {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [Parameter(Mandatory = $true)][string]$Title,
        [AllowEmptyString()][string]$Description = '',
        [string]$Impact,
        [string]$Risk = 'Safe',
        [switch]$RequiresReboot,
        [string]$BlockReason,
        $ToolTipContent,
        [string]$Tag
    )

    $stack = New-Object System.Windows.Controls.StackPanel

    $line1 = New-Object System.Windows.Controls.DockPanel
    $line1.LastChildFill = $true
    $statusPanel = New-Object System.Windows.Controls.StackPanel
    $statusPanel.Orientation = 'Horizontal'
    $statusPanel.VerticalAlignment = 'Center'
    $statusPanel.Margin = New-Object System.Windows.Thickness(12, 0, 0, 0)
    [System.Windows.Controls.DockPanel]::SetDock($statusPanel, 'Right')

    $isBlocked = -not [string]::IsNullOrWhiteSpace($BlockReason)
    if ($isBlocked) {
        [void]$statusPanel.Children.Add((New-OptiKitText -Ui $Ui -Text 'Bloqueado' -Style 'Text.Caption' -Brush 'Brush.Danger'))
    }
    $applied = New-OptiKitText -Ui $Ui -Text 'Aplicado' -Style 'Text.Caption' -Brush 'Brush.Success'
    $applied.Visibility = 'Collapsed'
    if ($isBlocked) {
        $applied.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)
    }
    [void]$statusPanel.Children.Add($applied)
    [void]$line1.Children.Add($statusPanel)
    $titleTb = New-OptiKitText -Ui $Ui -Text $Title -Style 'Text.Body' -Overflow Trim
    [void]$line1.Children.Add($titleTb)
    [void]$stack.Children.Add($line1)

    $meta = New-Object System.Windows.Controls.TextBlock
    $meta.Style = Get-OptiKitUiResource -Ui $Ui -Key 'Text.Meta'
    $meta.Margin = New-Object System.Windows.Thickness(12, 0, 0, 0)
    [System.Windows.Controls.DockPanel]::SetDock($meta, 'Right')
    $riskInfo = Get-OptiKitRiskLabel -Risk $Risk
    if ($riskInfo) {
        [void]$meta.Inlines.Add((New-OptiKitRun -Ui $Ui -Text $riskInfo.Text -Brush $riskInfo.Brush))
    }
    $tail = New-Object 'System.Collections.Generic.List[string]'
    if (-not [string]::IsNullOrWhiteSpace($Impact)) { [void]$tail.Add((Get-OptiKitImpactLabel -Impact $Impact)) }
    if ($RequiresReboot) { [void]$tail.Add('Requer reinício') }
    foreach ($part in $tail) {
        if ($meta.Inlines.Count -gt 0) { [void]$meta.Inlines.Add((New-OptiKitRun -Ui $Ui -Text ' · ')) }
        [void]$meta.Inlines.Add((New-OptiKitRun -Ui $Ui -Text $part))
    }
    $hasDescription = -not [string]::IsNullOrWhiteSpace($Description)
    if ($hasDescription -or ($meta.Inlines.Count -gt 0)) {
        $line2 = New-Object System.Windows.Controls.DockPanel
        $line2.LastChildFill = $true
        $line2.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
        if ($meta.Inlines.Count -gt 0) { [void]$line2.Children.Add($meta) }
        if ($hasDescription) {
            [void]$line2.Children.Add((New-OptiKitText -Ui $Ui -Text $Description -Style 'Text.Caption' -Overflow Trim))
        }
        [void]$stack.Children.Add($line2)
    }

    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Content = $stack
    $cb.Margin = New-Object System.Windows.Thickness(0, 0, 8, 2)
    if ($Tag) { $cb.Tag = $Tag }
    if ($null -ne $ToolTipContent) { $cb.ToolTip = $ToolTipContent }
    if ($isBlocked) { $cb.IsEnabled = $false }

    return @{
        CheckBox     = $cb
        BadgeApplied = $applied
        TitleText    = $titleTb
    }
}

function New-OptiKitGroupHeader {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [Parameter(Mandatory = $true)][string]$Text,
        [int]$Count = 0,
        [switch]$First
    )

    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'
    $top = if ($First) { 0 } else { 28 }
    $sp.Margin = New-Object System.Windows.Thickness(0, $top, 0, 8)
    [void]$sp.Children.Add((New-OptiKitText -Ui $Ui -Text $Text -Style 'Text.Subtitle'))
    if ($Count -gt 0) {
        $countTb = New-OptiKitText -Ui $Ui -Text ([string]$Count) -Style 'Text.Meta'
        $countTb.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)
        $countTb.VerticalAlignment = 'Center'
        [void]$sp.Children.Add($countTb)
    }
    return $sp
}

function New-OptiKitResponsiveGrid {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [Parameter(Mandatory = $true)][string]$Container,
        [Parameter(Mandatory = $true)][double]$MinColumnWidth
    )

    $grid = New-Object System.Windows.Controls.Primitives.UniformGrid
    $grid.Columns = 1
    $grid.Tag = $MinColumnWidth
    if (-not $Ui.ResponsiveGrids) { $Ui.ResponsiveGrids = @{} }
    if (-not $Ui.ResponsiveGrids.ContainsKey($Container)) {
        $Ui.ResponsiveGrids[$Container] = New-Object 'System.Collections.Generic.List[object]'
    }
    [void]$Ui.ResponsiveGrids[$Container].Add($grid)
    return $grid
}

function Update-OptiKitResponsiveGrids {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [Parameter(Mandatory = $true)][string]$Container,
        [Parameter(Mandatory = $true)][double]$Width
    )

    if (-not $Ui.ResponsiveGrids -or -not $Ui.ResponsiveGrids.ContainsKey($Container)) { return }
    foreach ($grid in $Ui.ResponsiveGrids[$Container]) {
        $cols = [int][Math]::Max(1, [Math]::Floor($Width / [double]$grid.Tag))
        if ($grid.Columns -ne $cols) { $grid.Columns = $cols }
    }
}

function Register-OptiKitResponsiveHost {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [Parameter(Mandatory = $true)][string]$Container
    )

    $element = $Ui[$Container]
    if (-not $element) { return }
    $name = $Container
    $element.Add_SizeChanged({
        param($sizeSender, $sizeArgs)
        Update-OptiKitResponsiveGrids -Ui $Ui -Container $name -Width $sizeArgs.NewSize.Width
    }.GetNewClosure())
}

function Add-OptiKitComboOption {
    param(
        [Parameter(Mandatory = $true)]$Combo,
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $item = New-Object System.Windows.Controls.ComboBoxItem
    $item.Content = $Text
    $item.Tag = $Value
    [void]$Combo.Items.Add($item)
}

function Get-OptiKitTweakCategoryOrder {
    return @(
        'Desempenho & Energia',
        'Privacidade & Telemetria',
        'Windows Update',
        'Interface & Windows 11',
        'Remoção de Bloatware (Appx)',
        'Avançado'
    )
}

function Get-OptiKitTweakImpactOrder {
    param([string]$Impact)
    switch ($Impact) {
        'Alto' { return 0 }
        'Médio' { return 1 }
        'Baixo' { return 2 }
        'Situacional' { return 3 }
        default { return 4 }
    }
}

function Get-OptiKitTweakRiskOrder {
    param([string]$Risk)
    switch ($Risk) {
        'Advanced' { return 0 }
        'Moderate' { return 1 }
        'Safe' { return 2 }
        default { return 3 }
    }
}

function Get-OptiKitTweakStatusOrder {
    param([string]$Status)
    switch ($Status) {
        'Applied' { return 0 }
        'Partial' { return 1 }
        'NotApplied' { return 2 }
        default { return 3 }
    }
}

function Get-OptiKitTweakStatusLabel {
    param([string]$Status)
    switch ($Status) {
        'Applied' { return 'Aplicado' }
        'Partial' { return 'Parcial' }
        'NotApplied' { return 'Não aplicado' }
        default { return 'Desconhecido' }
    }
}

function Get-OptiKitTweakGroupInfo {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Definition,
        [Parameter(Mandatory = $true)][string]$Sort,
        [string]$Status = 'Unknown'
    )

    $categoryOrder = Get-OptiKitTweakCategoryOrder
    $categoryIndex = [array]::IndexOf($categoryOrder, [string]$Definition.Category)
    if ($categoryIndex -lt 0) { $categoryIndex = 99 }

    switch ($Sort) {
        'Impact' {
            return @{
                Key   = ('Impact:{0}' -f $Definition.Impact)
                Label = (Get-OptiKitImpactLabel -Impact $Definition.Impact)
                Order = (Get-OptiKitTweakImpactOrder -Impact $Definition.Impact)
            }
        }
        'Risk' {
            $risk = Get-OptiKitRiskLabel -Risk $Definition.Risk
            $label = if ($risk) { [string]$risk.Text } else { 'Seguro' }
            return @{
                Key   = ('Risk:{0}' -f $Definition.Risk)
                Label = $label
                Order = (Get-OptiKitTweakRiskOrder -Risk $Definition.Risk)
            }
        }
        'Status' {
            return @{
                Key   = ('Status:{0}' -f $Status)
                Label = (Get-OptiKitTweakStatusLabel -Status $Status)
                Order = (Get-OptiKitTweakStatusOrder -Status $Status)
            }
        }
        'Reboot' {
            $reboot = [bool]$Definition.RequiresReboot
            return @{
                Key   = ('Reboot:{0}' -f $reboot)
                Label = if ($reboot) { 'Requer reinício' } else { 'Não requer reinício' }
                Order = if ($reboot) { 0 } else { 1 }
            }
        }
        'Title' {
            return @{ Key = 'All'; Label = 'Todos os ajustes'; Order = 0 }
        }
        default {
            return @{
                Key   = ('Category:{0}' -f $Definition.Category)
                Label = [string]$Definition.Category
                Order = $categoryIndex
            }
        }
    }
}

function Update-OptiKitTweakFilterButton {
    param([Parameter(Mandatory = $true)][hashtable]$Ui)

    if (-not $Ui.BtnClearTweakFilters -or -not $Ui.TweakViewState) { return }
    $view = $Ui.TweakViewState
    $active = ($view.Impact -ne 'All') -or ($view.Risk -ne 'All') -or ($view.Status -ne 'All')
    $Ui.BtnClearTweakFilters.Visibility = if ($active) { 'Visible' } else { 'Collapsed' }
}

function Update-OptiKitTweakPage {
    param([Parameter(Mandatory = $true)][hashtable]$Ui)

    if (-not $Ui.TweaksCategoriesHost) { return }
    if (-not $Ui.TweakViewState) {
        $Ui.TweakViewState = @{ Sort = 'Category'; Impact = 'All'; Risk = 'All'; Status = 'All' }
    }
    if (-not $Ui.TweakStatuses) { $Ui.TweakStatuses = @{} }

    $view = $Ui.TweakViewState
    $categoryOrder = Get-OptiKitTweakCategoryOrder
    $filtered = New-Object 'System.Collections.Generic.List[object]'

    foreach ($def in $Ui.TweakDefinitions) {
        if ($view.Impact -ne 'All' -and $def.Impact -ne $view.Impact) { continue }
        if ($view.Risk -ne 'All' -and $def.Risk -ne $view.Risk) { continue }

        $status = if ($Ui.TweakStatuses.ContainsKey($def.Key)) { [string]$Ui.TweakStatuses[$def.Key] } else { 'Unknown' }
        if ($view.Status -ne 'All' -and $status -ne $view.Status) { continue }
        [void]$filtered.Add($def)
    }

    $prepared = New-Object 'System.Collections.Generic.List[object]'
    foreach ($def in $filtered) {
        $status = if ($Ui.TweakStatuses.ContainsKey($def.Key)) { [string]$Ui.TweakStatuses[$def.Key] } else { 'Unknown' }
        $group = Get-OptiKitTweakGroupInfo -Definition $def -Sort $view.Sort -Status $status
        $categoryIndex = [array]::IndexOf($categoryOrder, [string]$def.Category)
        if ($categoryIndex -lt 0) { $categoryIndex = 99 }
        $impactOrder = Get-OptiKitTweakImpactOrder -Impact $def.Impact
        $riskOrder = Get-OptiKitTweakRiskOrder -Risk $def.Risk

        $secondary = switch ($view.Sort) {
            'Impact' { ($categoryIndex * 100) + ($riskOrder * 10) }
            'Risk' { ($impactOrder * 100) + ($categoryIndex * 10) }
            'Status' { ($impactOrder * 100) + ($categoryIndex * 10) }
            'Reboot' { ($impactOrder * 100) + ($categoryIndex * 10) }
            'Title' { 0 }
            default { ($impactOrder * 100) + ($riskOrder * 10) }
        }

        [void]$prepared.Add([pscustomobject]@{
            Definition = $def
            Status     = $status
            GroupKey   = $group.Key
            GroupLabel = $group.Label
            GroupOrder = [int]$group.Order
            Secondary  = [int]$secondary
        })
    }

    $sorted = @($prepared | Sort-Object @{ Expression = { $_.GroupOrder } }, @{ Expression = { $_.Secondary } }, @{ Expression = { $_.Definition.Title } })

    $groupCounts = @{}
    foreach ($item in $sorted) {
        if ($groupCounts.ContainsKey($item.GroupKey)) {
            $groupCounts[$item.GroupKey]++
        }
        else {
            $groupCounts[$item.GroupKey] = 1
        }
    }

    $Ui.TweaksCategoriesHost.Children.Clear()
    if ($Ui.ResponsiveGrids -and $Ui.ResponsiveGrids.ContainsKey('TweaksCategoriesHost')) {
        $Ui.ResponsiveGrids['TweaksCategoriesHost'].Clear()
    }
    for ($i = $Ui.SearchGroups.Count - 1; $i -ge 0; $i--) {
        if ($Ui.SearchGroups[$i].Page -eq 'Tweaks') {
            $Ui.SearchGroups.RemoveAt($i)
        }
    }

    $newEntries = @{}
    $firstGroup = $true
    $currentGroupKey = $null
    $grid = $null
    $entries = $null

    foreach ($item in $sorted) {
        $def = $item.Definition
        if ($item.GroupKey -ne $currentGroupKey) {
            $header = New-OptiKitGroupHeader -Ui $Ui -Text $item.GroupLabel -Count $groupCounts[$item.GroupKey] -First:$firstGroup
            $firstGroup = $false
            $grid = New-OptiKitResponsiveGrid -Ui $Ui -Container 'TweaksCategoriesHost' -MinColumnWidth 560
            $entries = New-Object 'System.Collections.Generic.List[object]'
            [void]$Ui.TweaksCategoriesHost.Children.Add($header)
            [void]$Ui.TweaksCategoriesHost.Children.Add($grid)
            [void]$Ui.SearchGroups.Add(@{ Page = 'Tweaks'; Header = $header; Container = $grid; Entries = $entries })
            $currentGroupKey = $item.GroupKey
        }

        $tweakVal = $def.Config
        $blockReason = $def.BlockReason
        $footerParts = New-Object 'System.Collections.Generic.List[string]'
        [void]$footerParts.Add((Get-OptiKitImpactLabel -Impact $tweakVal.impact))
        $riskInfo = Get-OptiKitRiskLabel -Risk $tweakVal.riskLevel
        if ($riskInfo) { [void]$footerParts.Add($riskInfo.Text) }
        if ($tweakVal.requiresReboot) { [void]$footerParts.Add('Requer reinício') }
        $alert = if ($blockReason) { 'Bloqueado neste hardware: {0}' -f $blockReason } else { $null }
        $tip = New-OptiKitToolTipContent -Ui $Ui -Title $tweakVal.title -Body $tweakVal.description -DetailLabel 'Justificativa técnica' -Detail $tweakVal.rationale -Footer ($footerParts -join ' · ') -Alert $alert

        $row = New-OptiKitItemRow -Ui $Ui -Title $tweakVal.title -Description $tweakVal.description -Impact $tweakVal.impact -Risk $tweakVal.riskLevel -RequiresReboot:([bool]$tweakVal.requiresReboot) -BlockReason $blockReason -ToolTipContent $tip -Tag $def.Key
        $cb = $row.CheckBox
        $cb.IsChecked = $Ui.SelectedTweakIds.Contains($def.Key)

        $key = [string]$def.Key
        $confirmText = $tweakVal.confirmMessage
        $cb.Add_Checked({
            if (-not [string]::IsNullOrWhiteSpace($confirmText) -and (-not $Ui.SuppressConfirmDialog)) {
                $ans = [System.Windows.MessageBox]::Show($Ui.Window, $confirmText, 'Confirmar ajuste', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
                if ($ans -ne [System.Windows.MessageBoxResult]::Yes) {
                    $this.IsChecked = $false
                    return
                }
            }
            [void]$Ui.SelectedTweakIds.Add($key)
            Update-SelectionCounter -Ui $Ui
        }.GetNewClosure())
        $cb.Add_Unchecked({
            [void]$Ui.SelectedTweakIds.Remove($key)
            Update-SelectionCounter -Ui $Ui
        }.GetNewClosure())

        if ($item.Status -eq 'Applied') {
            $row.BadgeApplied.Visibility = 'Visible'
        }
        else {
            $row.BadgeApplied.Visibility = 'Collapsed'
        }

        [void]$grid.Children.Add($cb)
        $entry = @{
            CheckBox     = $cb
            Card         = $cb
            BadgeApplied = $row.BadgeApplied
            Config       = $tweakVal
            BlockReason  = $blockReason
            SearchText   = $def.SearchText
            Category     = $def.Category
            Impact       = $def.Impact
            Risk         = $def.Risk
            RequiresReboot = $def.RequiresReboot
        }
        $newEntries[$key] = $entry
        [void]$entries.Add($entry)
    }

    $Ui.TweakCheckboxes = $newEntries
    $Ui.TweaksFilteredEmpty = ($sorted.Count -eq 0)

    if ($Ui.TxtTweakCount) {
        $total = $Ui.TweakDefinitions.Count
        $shown = $sorted.Count
        $Ui.TxtTweakCount.Text = if ($shown -eq $total) {
            Format-OptiKitCount -Count $total -Singular 'ajuste' -Plural 'ajustes'
        }
        else {
            ('{0} de {1} ajustes' -f $shown, $total)
        }
    }

    if ($Ui.TxtTweaksEmpty) {
        if ($Ui.TweaksFilteredEmpty) {
            $Ui.TxtTweaksEmpty.Text = 'Nenhum ajuste com esses filtros. Ajuste a organização ou limpe os filtros.'
            $Ui.TxtTweaksEmpty.Visibility = 'Visible'
        }
        else {
            $Ui.TxtTweaksEmpty.Visibility = 'Collapsed'
        }
    }

    if ($Ui.TweaksCategoriesHost.ActualWidth -gt 0) {
        Update-OptiKitResponsiveGrids -Ui $Ui -Container 'TweaksCategoriesHost' -Width $Ui.TweaksCategoriesHost.ActualWidth
    }

    Update-OptiKitTweakFilterButton -Ui $Ui
    Update-SelectionCounter -Ui $Ui
}

function Set-OptiKitTweakView {
    param([Parameter(Mandatory = $true)][hashtable]$Ui)

    if (-not $Ui.TweakViewState) {
        $Ui.TweakViewState = @{ Sort = 'Category'; Impact = 'All'; Risk = 'All'; Status = 'All' }
    }
    if ($Ui.CmbTweakSort -and $Ui.CmbTweakSort.SelectedItem) {
        $Ui.TweakViewState.Sort = [string]$Ui.CmbTweakSort.SelectedItem.Tag
    }
    if ($Ui.CmbTweakImpact -and $Ui.CmbTweakImpact.SelectedItem) {
        $Ui.TweakViewState.Impact = [string]$Ui.CmbTweakImpact.SelectedItem.Tag
    }
    if ($Ui.CmbTweakRisk -and $Ui.CmbTweakRisk.SelectedItem) {
        $Ui.TweakViewState.Risk = [string]$Ui.CmbTweakRisk.SelectedItem.Tag
    }
    if ($Ui.CmbTweakStatus -and $Ui.CmbTweakStatus.SelectedItem) {
        $Ui.TweakViewState.Status = [string]$Ui.CmbTweakStatus.SelectedItem.Tag
    }

    Update-OptiKitTweakPage -Ui $Ui
    if ($Ui.TxtSearchBox) {
        Invoke-SearchFilter -Ui $Ui -Query $Ui.TxtSearchBox.Text
    }
    Update-OptiKitTweakFilterButton -Ui $Ui
}

function Get-OptiKitDiagnosticVisual {
    param([string]$Status)
    switch ($Status) {
        'Error' { return @{ Glyph = [char]0xEA39; Brush = 'Brush.Danger'; Label = 'Problema'; Order = 0 } }
        'Warn' { return @{ Glyph = [char]0xE7BA; Brush = 'Brush.Warning'; Label = 'Aviso'; Order = 1 } }
        'Info' { return @{ Glyph = [char]0xE946; Brush = 'Brush.Text.Tertiary'; Label = 'Informativo'; Order = 3 } }
        'OK' { return @{ Glyph = [char]0xE930; Brush = 'Brush.Success'; Label = 'OK'; Order = 4 } }
        default { return @{ Glyph = [char]0xE9CE; Brush = 'Brush.Text.Tertiary'; Label = 'Não verificado'; Order = 2 } }
    }
}

function Format-OptiKitDiagnosticsSummary {
    param([array]$Items)

    $all = @($Items)
    if ($all.Count -eq 0) { return 'Somente leitura. Nenhuma verificação disponível.' }
    $parts = New-Object 'System.Collections.Generic.List[string]'
    $err = @($all | Where-Object { $_.Status -eq 'Error' }).Count
    $warn = @($all | Where-Object { $_.Status -eq 'Warn' }).Count
    $ok = @($all | Where-Object { $_.Status -eq 'OK' }).Count
    $other = $all.Count - $err - $warn - $ok
    if ($err -gt 0) { [void]$parts.Add((Format-OptiKitCount -Count $err -Singular 'problema' -Plural 'problemas')) }
    if ($warn -gt 0) { [void]$parts.Add((Format-OptiKitCount -Count $warn -Singular 'aviso' -Plural 'avisos')) }
    if ($ok -gt 0) { [void]$parts.Add(('{0} OK' -f $ok)) }
    if ($other -gt 0) { [void]$parts.Add((Format-OptiKitCount -Count $other -Singular 'informativo' -Plural 'informativos')) }
    $joined = if ($parts.Count -gt 1) { (($parts[0..($parts.Count - 2)]) -join ', ') + ' e ' + $parts[$parts.Count - 1] } else { $parts[0] }
    return ('Somente leitura. {0}.' -f $joined)
}

function New-OptiKitDiagnosticRow {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [Parameter(Mandatory = $true)][pscustomobject]$Item
    )

    $visual = Get-OptiKitDiagnosticVisual -Status $Item.Status
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = New-Object System.Windows.Thickness(0, 14, 0, 14)
    $colIcon = New-Object System.Windows.Controls.ColumnDefinition
    $colIcon.Width = [System.Windows.GridLength]::Auto
    $colBody = New-Object System.Windows.Controls.ColumnDefinition
    $colBody.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    [void]$grid.ColumnDefinitions.Add($colIcon)
    [void]$grid.ColumnDefinitions.Add($colBody)

    $icon = New-OptiKitText -Ui $Ui -Text ([string]$visual.Glyph) -Style 'Text.Icon' -Brush $visual.Brush
    $icon.VerticalAlignment = 'Top'
    $icon.Margin = New-Object System.Windows.Thickness(0, 2, 12, 0)
    [void]$grid.Children.Add($icon)

    $body = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetColumn($body, 1)

    $head = New-Object System.Windows.Controls.DockPanel
    $head.LastChildFill = $true
    $label = New-OptiKitText -Ui $Ui -Text $visual.Label -Style 'Text.Caption' -Brush $visual.Brush
    $label.Margin = New-Object System.Windows.Thickness(12, 0, 0, 0)
    $label.VerticalAlignment = 'Center'
    [System.Windows.Controls.DockPanel]::SetDock($label, 'Right')
    [void]$head.Children.Add($label)
    [void]$head.Children.Add((New-OptiKitText -Ui $Ui -Text ([string]$Item.Title) -Style 'Text.BodyStrong' -Overflow Trim))
    [void]$body.Children.Add($head)

    $summary = New-OptiKitText -Ui $Ui -Text ([string]$Item.Summary) -Style 'Text.Caption' -Overflow Wrap -Brush 'Brush.Text.Primary'
    $summary.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
    [void]$body.Children.Add($summary)

    if (-not [string]::IsNullOrWhiteSpace([string]$Item.Detail)) {
        $detail = New-OptiKitText -Ui $Ui -Text ([string]$Item.Detail) -Style 'Text.Meta' -Overflow Wrap
        $detail.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
        [void]$body.Children.Add($detail)
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Item.ActionText)) {
        $action = New-OptiKitText -Ui $Ui -Style 'Text.Caption' -Overflow Wrap
        $action.Margin = New-Object System.Windows.Thickness(0, 6, 0, 0)
        if (-not [string]::IsNullOrWhiteSpace([string]$Item.ActionUrl)) {
            $link = New-Object System.Windows.Documents.Hyperlink
            [void]$link.Inlines.Add((New-Object System.Windows.Documents.Run([string]$Item.ActionText)))
            $link.Foreground = Get-OptiKitUiResource -Ui $Ui -Key 'Brush.Accent'
            $link.NavigateUri = [Uri]$Item.ActionUrl
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
            [void]$action.Inlines.Add($link)
        }
        else {
            $action.Text = ('Recomendação: {0}' -f $Item.ActionText)
        }
        [void]$body.Children.Add($action)
    }

    [void]$grid.Children.Add($body)
    return $grid
}

function Get-OptiKitGameIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$ProfileKey,
        [Parameter(Mandatory = $true)][pscustomobject]$GameProfile
    )

    $shortName = [string]$GameProfile.shortName
    if ([string]::IsNullOrWhiteSpace($shortName)) {
        $shortName = switch ($ProfileKey) {
            'ProfileValorant' { 'VAL' }
            'ProfileCS2' { 'CS2' }
            'ProfileUE5' { 'UE5' }
            'GlobalGamingTools' { 'GLB' }
            default {
                $words = @(([string]$GameProfile.gameName -split '\s+') | Where-Object { $_ })
                $initials = ($words | ForEach-Object { $_.Substring(0, 1) } | Select-Object -First 3) -join ''
                if ($initials) { $initials } else { 'GAME' }
            }
        }
    }

    $accentBrush = switch ([string]$GameProfile.accent) {
        'Valorant' { 'Brush.Danger' }
        'CS2' { 'Brush.Warning' }
        'UE5' { 'Brush.Accent' }
        'Global' { 'Brush.Success' }
        default { 'Brush.Text.Tertiary' }
    }

    return @{
        ShortName   = $shortName.ToUpperInvariant()
        AccentBrush = $accentBrush
    }
}

function New-OptiKitGameSection {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [Parameter(Mandatory = $true)][pscustomobject]$GameProfile,
        [string]$ProfileKey = '',
        [string]$ExePath,
        [switch]$First
    )

    $panel = New-Object System.Windows.Controls.StackPanel
    $top = if ($First) { 0 } else { 32 }
    $panel.Margin = New-Object System.Windows.Thickness(0, $top, 0, 0)

    $identity = Get-OptiKitGameIdentity -ProfileKey $ProfileKey -GameProfile $GameProfile
    $optimizationCount = @($GameProfile.optimizations).Count
    $countLabel = if ($GameProfile.status -eq 'global') {
        Format-OptiKitCount -Count $optimizationCount -Singular 'ferramenta' -Plural 'ferramentas'
    }
    else {
        Format-OptiKitCount -Count $optimizationCount -Singular 'otimização' -Plural 'otimizações'
    }

    $statusText = 'Executável detectado'
    $statusBrush = 'Brush.Success'
    if ($GameProfile.status -eq 'comingSoon') {
        $statusText = 'Em breve'
        $statusBrush = 'Brush.Text.Tertiary'
    }
    elseif ($GameProfile.status -eq 'global') {
        $statusText = 'Ferramentas globais'
        $statusBrush = 'Brush.Text.Tertiary'
    }
    elseif ([string]::IsNullOrWhiteSpace($ExePath)) {
        $statusText = 'Executável não encontrado'
        $statusBrush = 'Brush.Warning'
    }

    $head = New-Object System.Windows.Controls.Grid
    $colTile = New-Object System.Windows.Controls.ColumnDefinition
    $colTile.Width = [System.Windows.GridLength]::Auto
    $colTitle = New-Object System.Windows.Controls.ColumnDefinition
    $colTitle.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $colMeta = New-Object System.Windows.Controls.ColumnDefinition
    $colMeta.Width = [System.Windows.GridLength]::Auto
    [void]$head.ColumnDefinitions.Add($colTile)
    [void]$head.ColumnDefinitions.Add($colTitle)
    [void]$head.ColumnDefinitions.Add($colMeta)

    $tile = New-Object System.Windows.Controls.Border
    $tile.Width = 36
    $tile.Height = 36
    $tile.CornerRadius = New-Object System.Windows.CornerRadius(4)
    $tile.Background = Get-OptiKitUiResource -Ui $Ui -Key 'Brush.Bg.Surface'
    $tile.Margin = New-Object System.Windows.Thickness(0, 0, 12, 0)
    $tile.VerticalAlignment = 'Top'
    $logoData = $null
    if ($Ui.Configs -and $Ui.Configs.GameLogos -and -not [string]::IsNullOrWhiteSpace($ProfileKey)) {
        $logoProp = $Ui.Configs.GameLogos.PSObject.Properties[$ProfileKey]
        if ($logoProp -and -not [string]::IsNullOrWhiteSpace([string]$logoProp.Value)) {
            $logoData = [string]$logoProp.Value
        }
    }

    $tileChild = $null
    if ($logoData) {
        try {
            $logo = New-Object System.Windows.Shapes.Path
            $logo.Data = [System.Windows.Media.Geometry]::Parse($logoData)
            $logo.Fill = Get-OptiKitUiResource -Ui $Ui -Key $identity.AccentBrush
            $logo.Stretch = 'Uniform'
            $logo.Width = 24
            $logo.Height = 24
            $logo.HorizontalAlignment = 'Center'
            $logo.VerticalAlignment = 'Center'
            $tileChild = $logo
        }
        catch {
            Write-Verbose ("Logo inválido para '{0}': {1}" -f $ProfileKey, $_.Exception.Message)
        }
    }
    if (-not $tileChild) {
        $monogram = New-OptiKitText -Ui $Ui -Text $identity.ShortName -Style 'Text.Meta' -Brush $identity.AccentBrush
        $monogram.FontWeight = 'SemiBold'
        $monogram.HorizontalAlignment = 'Center'
        $monogram.VerticalAlignment = 'Center'
        $tileChild = $monogram
    }
    $tile.Child = $tileChild
    [System.Windows.Controls.Grid]::SetColumn($tile, 0)
    [void]$head.Children.Add($tile)

    $titleStack = New-Object System.Windows.Controls.StackPanel
    $titleStack.Orientation = 'Vertical'
    $titleStack.VerticalAlignment = 'Center'
    $titleRow = New-Object System.Windows.Controls.StackPanel
    $titleRow.Orientation = 'Horizontal'
    [void]$titleRow.Children.Add((New-OptiKitText -Ui $Ui -Text ([string]$GameProfile.gameName) -Style 'Text.Subtitle' -Overflow Trim))
    if ($GameProfile.status -eq 'comingSoon') {
        $soon = New-OptiKitText -Ui $Ui -Text 'Em breve' -Style 'Text.Meta'
        $soon.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)
        $soon.VerticalAlignment = 'Center'
        [void]$titleRow.Children.Add($soon)
    }
    [void]$titleStack.Children.Add($titleRow)
    $countText = New-OptiKitText -Ui $Ui -Text $countLabel -Style 'Text.Meta'
    $countText.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
    [void]$titleStack.Children.Add($countText)
    [System.Windows.Controls.Grid]::SetColumn($titleStack, 1)
    [void]$head.Children.Add($titleStack)

    $rightStack = New-Object System.Windows.Controls.StackPanel
    $rightStack.Orientation = 'Vertical'
    $rightStack.HorizontalAlignment = 'Right'
    $rightStack.VerticalAlignment = 'Center'
    $metaText = (@($GameProfile.engine, $GameProfile.antiCheat) | Where-Object { $_ }) -join ' · '
    if (-not [string]::IsNullOrWhiteSpace($metaText)) {
        $meta = New-OptiKitText -Ui $Ui -Text $metaText -Style 'Text.Meta'
        $meta.HorizontalAlignment = 'Right'
        [void]$rightStack.Children.Add($meta)
    }
    $status = New-OptiKitText -Ui $Ui -Text $statusText -Style 'Text.Meta' -Brush $statusBrush
    $status.HorizontalAlignment = 'Right'
    $status.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
    [void]$rightStack.Children.Add($status)
    [System.Windows.Controls.Grid]::SetColumn($rightStack, 2)
    [void]$head.Children.Add($rightStack)

    [void]$panel.Children.Add($head)

    if (-not [string]::IsNullOrWhiteSpace([string]$GameProfile.warning)) {
        $warning = New-OptiKitText -Ui $Ui -Text ([string]$GameProfile.warning) -Style 'Text.Caption' -Overflow Wrap
        $warning.Margin = New-Object System.Windows.Thickness(0, 4, 0, 12)
        $warning.MaxWidth = 760
        $warning.HorizontalAlignment = 'Left'
        [void]$panel.Children.Add($warning)
    }

    $exeText = $null
    $browse = $null
    if ($GameProfile.status -eq 'active') {
        $exeRow = New-Object System.Windows.Controls.DockPanel
        $exeRow.LastChildFill = $true
        $exeRow.Margin = New-Object System.Windows.Thickness(0, 0, 8, 8)

        $browse = New-Object System.Windows.Controls.Button
        $browse.Style = Get-OptiKitUiResource -Ui $Ui -Key 'Button.Subtle'
        [System.Windows.Controls.DockPanel]::SetDock($browse, 'Right')
        [void]$exeRow.Children.Add($browse)

        $exeText = New-OptiKitText -Ui $Ui -Style 'Text.Caption' -Overflow Trim
        $exeText.VerticalAlignment = 'Center'
        [void]$exeRow.Children.Add($exeText)
        Set-OptiKitGameExeLabel -Ui $Ui -Label $exeText -Button $browse -ExePath $ExePath
        [void]$panel.Children.Add($exeRow)
    }

    $grid = New-OptiKitResponsiveGrid -Ui $Ui -Container 'GameProfilesHost' -MinColumnWidth 560
    [void]$panel.Children.Add($grid)

    return @{
        Panel        = $panel
        Grid         = $grid
        ExeText      = $exeText
        BrowseButton = $browse
    }
}

function Set-OptiKitGameExeLabel {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [Parameter(Mandatory = $true)][System.Windows.Controls.TextBlock]$Label,
        [System.Windows.Controls.Button]$Button,
        [string]$ExePath
    )

    if ([string]::IsNullOrWhiteSpace($ExePath)) {
        $Label.Text = 'Executável não encontrado no caminho padrão.'
        $Label.Foreground = Get-OptiKitUiResource -Ui $Ui -Key 'Brush.Warning'
        $Label.ToolTip = $null
        if ($Button) { $Button.Content = 'Selecionar executável' }
        return
    }
    $Label.Text = ('Executável: {0}' -f (Split-Path -Path $ExePath -Leaf))
    $Label.Foreground = Get-OptiKitUiResource -Ui $Ui -Key 'Brush.Text.Secondary'
    $Label.ToolTip = $ExePath
    if ($Button) { $Button.Content = 'Alterar' }
}

function Update-SelectionCounter {
    param([Parameter(Mandatory = $true)][hashtable]$Ui)

    $count = 0
    if ($Ui.SelectedTweakIds) { $count += $Ui.SelectedTweakIds.Count }
    foreach ($entry in $Ui.AppCheckboxes.Values) {
        if ($entry.CheckBox.IsChecked -eq $true) { $count++ }
    }
    foreach ($entry in $Ui.GameOptCheckboxes.Values) {
        if ($entry.CheckBox.IsChecked -eq $true) { $count++ }
    }

    $Ui.SelectionCount = $count
    if ($Ui.TxtSelectionCounter) {
        $Ui.TxtSelectionCounter.Text = Format-OptiKitSelectionCount -Count $count
    }
}

function Select-OptiKitPreset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$PresetKey
    )

    $Ui.SuppressConfirmDialog = $true
    try {
        foreach ($entry in $Ui.AppCheckboxes.Values) { $entry.CheckBox.IsChecked = $false }
        foreach ($entry in $Ui.GameOptCheckboxes.Values) { $entry.CheckBox.IsChecked = $false }
        if ($Ui.SelectedTweakIds) { $Ui.SelectedTweakIds.Clear() }

        if ([string]::IsNullOrWhiteSpace($PresetKey)) {
            Update-OptiKitTweakPage -Ui $Ui
            Update-SelectionCounter -Ui $Ui
            return
        }

        $presetProp = $Ui.Configs.Presets.PSObject.Properties[$PresetKey]
        if (-not $presetProp) {
            Write-OptimizerLog -Level WARN -Message ("Preset '{0}' não encontrado em presets.json." -f $PresetKey)
            Update-OptiKitTweakPage -Ui $Ui
            Update-SelectionCounter -Ui $Ui
            return
        }

        $preset = $presetProp.Value
        foreach ($tid in @($preset.tweaks)) {
            $definition = if ($Ui.TweakDefinitionMap) { $Ui.TweakDefinitionMap[$tid] } else { $null }
            if (-not $definition) {
                Write-OptimizerLog -Level WARN -Message ("Tweak '{0}' do preset '{1}' não está disponível neste Windows." -f $tid, $PresetKey)
                continue
            }
            if ($tid -eq 'WPFTweaksEnableHAGS' -and (Test-OptiKitHagsVramConstrained -Hardware $Ui.Hardware)) {
                Write-OptimizerLog -Level WARN -Message ("HAGS ignorado no preset '{0}': GPU com {1} GB de VRAM; ative manualmente se usar Frame Generation." -f $PresetKey, $Ui.Hardware.GpuVramGB)
                continue
            }
            if ($definition.BlockReason) {
                Write-OptimizerLog -Level WARN -Message ("Tweak '{0}' ignorado no preset '{1}': {2}" -f $tid, $PresetKey, $definition.BlockReason)
                continue
            }
            [void]$Ui.SelectedTweakIds.Add($tid)
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

        Update-OptiKitTweakPage -Ui $Ui
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
        foreach ($entry in $Ui.GameOptCheckboxes.Values) { $entry.CheckBox.IsChecked = $false }
        if ($Ui.SelectedTweakIds) { $Ui.SelectedTweakIds.Clear() }

        foreach ($tweakId in @($Selection.Tweaks)) {
            $definition = if ($Ui.TweakDefinitionMap) { $Ui.TweakDefinitionMap[$tweakId] } else { $null }
            if (-not $definition) {
                Write-OptimizerLog -Level WARN -Message ("Tweak '{0}' do perfil não está disponível neste Windows." -f $tweakId)
                continue
            }
            if ($definition.BlockReason) {
                Write-OptimizerLog -Level WARN -Message ("Tweak '{0}' ignorado ao importar perfil: {1}" -f $tweakId, $definition.BlockReason)
                continue
            }
            [void]$Ui.SelectedTweakIds.Add($tweakId)
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

        Update-OptiKitTweakPage -Ui $Ui
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
    $Ui.TweakStatuses = @{}

    if ($StateReport.Tweaks) {
        foreach ($tid in $StateReport.Tweaks.Keys) {
            $Ui.TweakStatuses[$tid] = [string]$StateReport.Tweaks[$tid]
        }
    }

    $needsTweakRebuild = ($Ui.TweakViewState -and (($Ui.TweakViewState.Sort -eq 'Status') -or ($Ui.TweakViewState.Status -ne 'All')))
    if ($needsTweakRebuild) {
        Update-OptiKitTweakPage -Ui $Ui
        if ($Ui.TxtSearchBox) {
            Invoke-SearchFilter -Ui $Ui -Query $Ui.TxtSearchBox.Text
        }
    }
    elseif ($StateReport.Tweaks) {
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

    if ($Ui.TxtDiagnosticsSummary) {
        $Ui.TxtDiagnosticsSummary.Text = Format-OptiKitDiagnosticsSummary -Items $Items
    }

    $ordered = for ($i = 0; $i -lt $Items.Count; $i++) {
        [pscustomobject]@{
            Item  = $Items[$i]
            Order = (Get-OptiKitDiagnosticVisual -Status $Items[$i].Status).Order
            Index = $i
        }
    }
    $sorted = @($ordered | Sort-Object Order, Index)

    for ($i = 0; $i -lt $sorted.Count; $i++) {
        if ($i -gt 0) {
            $divider = New-Object System.Windows.Controls.Border
            $divider.Style = Get-OptiKitUiResource -Ui $Ui -Key 'Divider'
            [void]$Ui.DiagnosticsHost.Children.Add($divider)
        }
        [void]$Ui.DiagnosticsHost.Children.Add((New-OptiKitDiagnosticRow -Ui $Ui -Item $sorted[$i].Item))
    }
}

function Invoke-SearchFilter {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [AllowEmptyString()][string]$Query
    )

    $q = if ($Query) { $Query.Trim().ToLowerInvariant() } else { '' }
    $tweaksFilteredEmpty = [bool]$Ui.TweaksFilteredEmpty
    foreach ($coll in @($Ui.AppCheckboxes.Values, $Ui.TweakCheckboxes.Values, $Ui.GameOptCheckboxes.Values)) {
        foreach ($entry in $coll) {
            $entry.Card.Visibility = if ([string]::IsNullOrEmpty($q) -or $entry.SearchText.Contains($q)) { 'Visible' } else { 'Collapsed' }
        }
    }

    $visibleByPage = @{ Apps = 0; Tweaks = 0; Games = 0 }
    # Sem @(): no PS 5.1, @($hashtable.Lista) com List[object] de hashtables lança "Os tipos de argumento não correspondem".
    foreach ($group in $Ui.SearchGroups) {
        $visible = @($group.Entries | Where-Object { $_.Card.Visibility -eq 'Visible' }).Count
        $groupVisibility = if ([string]::IsNullOrEmpty($q) -or ($visible -gt 0)) { 'Visible' } else { 'Collapsed' }
        if ($group.Header) { $group.Header.Visibility = $groupVisibility }
        if ($group.Container) { $group.Container.Visibility = $groupVisibility }
        $visibleByPage[$group.Page] += $visible
    }

    $pageOrder = @('Apps', 'Tweaks', 'Games')
    $pageNames = @{ Apps = 'Instalar apps'; Tweaks = 'Ajustes do Windows'; Games = 'Jogos' }
    $emptyMap = @{ Apps = 'TxtAppsEmpty'; Tweaks = 'TxtTweaksEmpty'; Games = 'TxtGamesEmpty' }
    foreach ($page in $pageOrder) {
        $emptyTb = $Ui[$emptyMap[$page]]
        if (-not $emptyTb) { continue }
        if ((-not [string]::IsNullOrEmpty($q)) -and ($visibleByPage[$page] -eq 0)) {
            $elsewhere = @($pageOrder | Where-Object { ($_ -ne $page) -and ($visibleByPage[$_] -gt 0) } | ForEach-Object { '{0} ({1})' -f $pageNames[$_], $visibleByPage[$_] })
            $emptyTb.Text = if ($elsewhere.Count -gt 0) {
                'Nada nesta página para "{0}". Resultados em: {1}.' -f $Query.Trim(), ($elsewhere -join ', ')
            }
            else {
                'Nenhum resultado para "{0}". Tente outro termo ou limpe a busca.' -f $Query.Trim()
            }
            $emptyTb.Visibility = 'Visible'
        }
        elseif (($page -eq 'Tweaks') -and [string]::IsNullOrEmpty($q) -and $tweaksFilteredEmpty) {
            $emptyTb.Text = 'Nenhum ajuste com esses filtros. Ajuste a organização ou limpe os filtros.'
            $emptyTb.Visibility = 'Visible'
        }
        else {
            $emptyTb.Visibility = 'Collapsed'
        }
    }
    return $visibleByPage
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
        SelectionCount        = 0
        SearchGroups          = (New-Object 'System.Collections.Generic.List[object]')
        ResponsiveGrids       = @{}
        TweakDefinitions      = (New-Object 'System.Collections.Generic.List[object]')
        TweakDefinitionMap    = @{}
        TweakStatuses         = @{}
        TweakViewState        = @{ Sort = 'Category'; Impact = 'All'; Risk = 'All'; Status = 'All' }
        SelectedTweakIds      = (New-Object 'System.Collections.Generic.HashSet[string]')
        TweaksFilteredEmpty   = $false
    }

    $controlNames = @(
        'BadgeDryRun', 'BadgeUpdate', 'TxtUpdateBadge', 'TxtHardwareSummary', 'TxtSearchBox', 'BtnClearSearch',
        'ImgOptiKitLogo', 'TxtBrandFallback',
        'MainTabControl', 'AppsCategoriesHost', 'BtnUncheckAllApps',
        'TweaksCategoriesHost', 'BtnRefreshState', 'BtnUncheckAllTweaks',
        'CmbTweakSort', 'CmbTweakImpact', 'CmbTweakRisk', 'CmbTweakStatus', 'BtnClearTweakFilters', 'TxtTweakCount',
        'GameProfilesHost',
        'BtnRefreshDiagnostics', 'TxtDiagnosticsSummary', 'DiagnosticsHost',
        'BtnResetNetwork', 'BtnRunSfcDism', 'BtnCancelMaintenance', 'BtnRebootUefi', 'BtnClearTemp', 'BtnOpenBackupsDir',
        'BtnExportProfile', 'BtnImportProfile', 'BtnExportReport',
        'CmbDohProvider', 'BtnApplyDoh', 'BtnUndoDoh', 'BtnWingetUpgrade', 'BtnAdvancedCleanup',
        'GridStartupItems', 'BtnEnableStartup', 'BtnDisableStartup', 'BtnRefreshStartup',
        'CmbPresets', 'BtnClearSelection', 'TxtSelectionCounter',
        'BtnViewApplied', 'BtnUndoSelected', 'BtnUndoAll', 'BtnApplySelected',
        'MainProgressBar', 'TxtStatusMessage', 'TxtConsoleOutput',
        'NavList', 'SelectionBar', 'LogPanel', 'BtnToggleLog', 'TxtAppsEmpty', 'TxtTweaksEmpty', 'TxtGamesEmpty'
    )
    foreach ($name in $controlNames) {
        $ui[$name] = $Window.FindName($name)
    }

    $ui.DohSupported = Test-OptiKitDohSupported -Hardware $Hardware

    if ($ui.ImgOptiKitLogo -and $ui.Configs -and -not [string]::IsNullOrWhiteSpace([string]$ui.Configs.LogoBase64)) {
        try {
            $logoBytes = [Convert]::FromBase64String([string]$ui.Configs.LogoBase64)
            $logoStream = New-Object System.IO.MemoryStream
            $logoStream.Write($logoBytes, 0, $logoBytes.Length)
            $logoStream.Position = 0
            $logoImage = New-Object System.Windows.Media.Imaging.BitmapImage
            $logoImage.BeginInit()
            $logoImage.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $logoImage.StreamSource = $logoStream
            $logoImage.EndInit()
            $logoImage.Freeze()
            $ui.ImgOptiKitLogo.Source = $logoImage
            $logoStream.Dispose()
            if ($ui.TxtBrandFallback) { $ui.TxtBrandFallback.Visibility = 'Collapsed' }
        }
        catch {
            Write-OptimizerLog -Level WARN -Message ("Falha ao carregar a logo: {0}" -f $_.Exception.Message)
            if ($ui.ImgOptiKitLogo) { $ui.ImgOptiKitLogo.Visibility = 'Collapsed' }
            if ($ui.TxtBrandFallback) { $ui.TxtBrandFallback.Visibility = 'Visible' }
        }
    }
    elseif ($ui.TxtBrandFallback) {
        if ($ui.ImgOptiKitLogo) { $ui.ImgOptiKitLogo.Visibility = 'Collapsed' }
        $ui.TxtBrandFallback.Visibility = 'Visible'
    }
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
        $ui.TxtHardwareSummary.Text = Format-OptiKitHardwareSummary -Summary $Hardware.Summary
    }

    foreach ($responsiveHost in @('AppsCategoriesHost', 'TweaksCategoriesHost', 'GameProfilesHost')) {
        Register-OptiKitResponsiveHost -Ui $ui -Container $responsiveHost
    }

    # 1. Instalar apps
    $appCategoryOrder = @(
        'Navegadores',
        'Comunicação',
        'Jogos & Launchers',
        'Runtimes & Utilitários',
        'Desenvolvimento'
    )
    $appProps = @($Configs.Apps.PSObject.Properties)
    $firstGroup = $true

    foreach ($catName in $appCategoryOrder) {
        $catItems = @($appProps | Where-Object { $_.Value.category -eq $catName })
        if ($catItems.Count -eq 0) { continue }

        $header = New-OptiKitGroupHeader -Ui $ui -Text $catName -Count $catItems.Count -First:$firstGroup
        $firstGroup = $false
        $grid = New-OptiKitResponsiveGrid -Ui $ui -Container 'AppsCategoriesHost' -MinColumnWidth 260
        $entries = New-Object 'System.Collections.Generic.List[object]'

        foreach ($ap in $catItems) {
            $appKey = $ap.Name
            $appVal = $ap.Value
            $tip = New-OptiKitToolTipContent -Ui $ui -Title $appVal.name -Body $appVal.description -Footer ('winget: {0}' -f $appVal.winget)
            $row = New-OptiKitItemRow -Ui $ui -Title $appVal.name -Description $appVal.description -ToolTipContent $tip -Tag $appKey
            $row.CheckBox.Add_Checked({ Update-SelectionCounter -Ui $ui }.GetNewClosure())
            $row.CheckBox.Add_Unchecked({ Update-SelectionCounter -Ui $ui }.GetNewClosure())
            [void]$grid.Children.Add($row.CheckBox)

            $entry = @{
                CheckBox   = $row.CheckBox
                Card       = $row.CheckBox
                Config     = $appVal
                SearchText = ("{0} {1} {2} {3}" -f $appVal.name, $appVal.winget, $appVal.category, $appVal.description).ToLowerInvariant()
            }
            $ui.AppCheckboxes[$appKey] = $entry
            [void]$entries.Add($entry)
        }

        [void]$ui.AppsCategoriesHost.Children.Add($header)
        [void]$ui.AppsCategoriesHost.Children.Add($grid)
        [void]$ui.SearchGroups.Add(@{ Page = 'Apps'; Header = $header; Container = $grid; Entries = $entries })
    }

    # 2. Ajustes do Windows
    $osTag = if ($Hardware.IsWin11) { 'Win11' } else { 'Win10' }
    $tweakProps = @($Configs.WinTweaks.PSObject.Properties)

    foreach ($tp in $tweakProps) {
        $t = $tp.Value
        if ((@($t.osSupport) -notcontains $osTag) -or ($null -ne $t.minBuild -and $Hardware.OsBuild -lt [int]$t.minBuild)) {
            continue
        }

        $definition = @{
            Key            = [string]$tp.Name
            Config         = $t
            Title          = [string]$t.title
            Description    = [string]$t.description
            Rationale      = [string]$t.rationale
            Category       = [string]$t.category
            Impact         = [string]$t.impact
            Risk           = [string]$t.riskLevel
            RequiresReboot = [bool]$t.requiresReboot
            BlockReason    = (Test-OptiKitTweakBlocked -Tweak $t -Hardware $Hardware)
            SearchText     = ("{0} {1} {2} {3} {4} {5}" -f $t.title, $t.description, $t.rationale, $t.category, $t.impact, $t.riskLevel).ToLowerInvariant()
        }
        [void]$ui.TweakDefinitions.Add($definition)
        $ui.TweakDefinitionMap[$tp.Name] = $definition
    }

    Update-OptiKitTweakPage -Ui $ui

    if ($ui.CmbTweakSort) {
        Add-OptiKitComboOption -Combo $ui.CmbTweakSort -Text 'Organizar: categoria' -Value 'Category'
        Add-OptiKitComboOption -Combo $ui.CmbTweakSort -Text 'Organizar: impacto' -Value 'Impact'
        Add-OptiKitComboOption -Combo $ui.CmbTweakSort -Text 'Organizar: risco' -Value 'Risk'
        Add-OptiKitComboOption -Combo $ui.CmbTweakSort -Text 'Organizar: reinício' -Value 'Reboot'
        Add-OptiKitComboOption -Combo $ui.CmbTweakSort -Text 'Organizar: estado' -Value 'Status'
        Add-OptiKitComboOption -Combo $ui.CmbTweakSort -Text 'Organizar: nome' -Value 'Title'

        Add-OptiKitComboOption -Combo $ui.CmbTweakImpact -Text 'Impacto: todos' -Value 'All'
        Add-OptiKitComboOption -Combo $ui.CmbTweakImpact -Text 'Impacto: alto' -Value 'Alto'
        Add-OptiKitComboOption -Combo $ui.CmbTweakImpact -Text 'Impacto: médio' -Value 'Médio'
        Add-OptiKitComboOption -Combo $ui.CmbTweakImpact -Text 'Impacto: baixo' -Value 'Baixo'
        Add-OptiKitComboOption -Combo $ui.CmbTweakImpact -Text 'Impacto: situacional' -Value 'Situacional'

        Add-OptiKitComboOption -Combo $ui.CmbTweakRisk -Text 'Risco: todos' -Value 'All'
        Add-OptiKitComboOption -Combo $ui.CmbTweakRisk -Text 'Risco: seguro' -Value 'Safe'
        Add-OptiKitComboOption -Combo $ui.CmbTweakRisk -Text 'Risco: moderado' -Value 'Moderate'
        Add-OptiKitComboOption -Combo $ui.CmbTweakRisk -Text 'Risco: avançado' -Value 'Advanced'

        Add-OptiKitComboOption -Combo $ui.CmbTweakStatus -Text 'Estado: todos' -Value 'All'
        Add-OptiKitComboOption -Combo $ui.CmbTweakStatus -Text 'Estado: aplicado' -Value 'Applied'
        Add-OptiKitComboOption -Combo $ui.CmbTweakStatus -Text 'Estado: não aplicado' -Value 'NotApplied'
        Add-OptiKitComboOption -Combo $ui.CmbTweakStatus -Text 'Estado: parcial' -Value 'Partial'
        Add-OptiKitComboOption -Combo $ui.CmbTweakStatus -Text 'Estado: desconhecido' -Value 'Unknown'

        $ui.CmbTweakSort.SelectedIndex = 0
        $ui.CmbTweakImpact.SelectedIndex = 0
        $ui.CmbTweakRisk.SelectedIndex = 0
        $ui.CmbTweakStatus.SelectedIndex = 0

        $ui.CmbTweakSort.Add_SelectionChanged({ Set-OptiKitTweakView -Ui $ui }.GetNewClosure())
        $ui.CmbTweakImpact.Add_SelectionChanged({ Set-OptiKitTweakView -Ui $ui }.GetNewClosure())
        $ui.CmbTweakRisk.Add_SelectionChanged({ Set-OptiKitTweakView -Ui $ui }.GetNewClosure())
        $ui.CmbTweakStatus.Add_SelectionChanged({ Set-OptiKitTweakView -Ui $ui }.GetNewClosure())

        if ($ui.BtnClearTweakFilters) {
            $ui.BtnClearTweakFilters.Add_Click({
                $ui.CmbTweakSort.SelectedIndex = 0
                $ui.CmbTweakImpact.SelectedIndex = 0
                $ui.CmbTweakRisk.SelectedIndex = 0
                $ui.CmbTweakStatus.SelectedIndex = 0
                Set-OptiKitTweakView -Ui $ui
            }.GetNewClosure())
        }
    }

    # 3. Jogos
    $firstSection = $true
    foreach ($gp in $Configs.GameProfiles.PSObject.Properties) {
        $profKey = $gp.Name
        $prof = $gp.Value

        $detectedExe = $null
        if ($prof.status -eq 'active') {
            $detectedExe = Find-GameExecutable -ProfileConfig $prof
            if ($detectedExe) {
                $ui.CustomGameExePaths[$profKey] = $detectedExe
            }
        }

        $section = New-OptiKitGameSection -Ui $ui -ProfileKey $profKey -GameProfile $prof -ExePath $detectedExe -First:$firstSection
        $firstSection = $false

        if ($section.BrowseButton) {
            $exeText = $section.ExeText
            $btnBrowse = $section.BrowseButton
            $btnBrowse.Add_Click({
                $dlg = New-Object System.Windows.Forms.OpenFileDialog
                $dlg.Filter = 'Executáveis (*.exe)|*.exe'
                $dlg.Title = ("Selecionar executável de {0}" -f $prof.gameName)
                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $ui.CustomGameExePaths[$profKey] = $dlg.FileName
                    Set-OptiKitGameExeLabel -Ui $ui -Label $exeText -Button $btnBrowse -ExePath $dlg.FileName
                }
            }.GetNewClosure())
        }

        $entries = New-Object 'System.Collections.Generic.List[object]'
        foreach ($opt in @($prof.optimizations)) {
            $tip = New-OptiKitToolTipContent -Ui $ui -Title $opt.title -Body $opt.description -DetailLabel 'Justificativa técnica' -Detail $opt.rationale -Footer (Get-OptiKitImpactLabel -Impact $opt.impact)
            $row = New-OptiKitItemRow -Ui $ui -Title $opt.title -Description $opt.description -Impact $opt.impact -Risk $opt.riskLevel -ToolTipContent $tip -Tag $opt.id
            $row.CheckBox.Add_Checked({ Update-SelectionCounter -Ui $ui }.GetNewClosure())
            $row.CheckBox.Add_Unchecked({ Update-SelectionCounter -Ui $ui }.GetNewClosure())
            [void]$section.Grid.Children.Add($row.CheckBox)

            $entry = @{
                CheckBox     = $row.CheckBox
                Card         = $row.CheckBox
                BadgeApplied = $row.BadgeApplied
                ProfileKey   = $profKey
                Profile      = $prof
                Config       = $opt
                SearchText   = ("{0} {1} {2} {3}" -f $prof.gameName, $opt.title, $opt.description, $opt.rationale).ToLowerInvariant()
            }
            $ui.GameOptCheckboxes[$opt.id] = $entry
            [void]$entries.Add($entry)
        }
        if ($entries.Count -eq 0) {
            $section.Grid.Visibility = 'Collapsed'
        }

        [void]$ui.GameProfilesHost.Children.Add($section.Panel)
        [void]$ui.SearchGroups.Add(@{ Page = 'Games'; Header = $null; Container = $section.Panel; Entries = $entries })
    }

    # 4. Popular ComboBox de Presets
    if ($ui.CmbPresets) {
        $placeholderItem = New-Object System.Windows.Controls.ComboBoxItem
        $placeholderItem.Content = 'Escolher preset'
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
            $counts = Invoke-SearchFilter -Ui $ui -Query $ui.TxtSearchBox.Text
            if ((-not [string]::IsNullOrWhiteSpace($ui.TxtSearchBox.Text)) -and ($ui.MainTabControl.SelectedIndex -gt 2)) {
                $pages = @('Apps', 'Tweaks', 'Games')
                $target = @(0, 1, 2) | Where-Object { $counts[$pages[$_]] -gt 0 } | Select-Object -First 1
                if ($null -ne $target) {
                    $ui.MainTabControl.SelectedIndex = $target
                }
            }
        }.GetNewClosure())
    }
    if ($ui.BtnClearSearch) {
        $ui.BtnClearSearch.Add_Click({
            $ui.TxtSearchBox.Text = ''
        }.GetNewClosure())
    }
    if ($ui.BtnToggleLog -and $ui.LogPanel) {
        $ui.BtnToggleLog.Add_Click({
            $ui.LogPanel.Visibility = if ($ui.LogPanel.Visibility -eq 'Visible') { 'Collapsed' } else { 'Visible' }
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
            $ui.SelectedTweakIds.Clear()
            Update-OptiKitTweakPage -Ui $ui
            Update-SelectionCounter -Ui $ui
        }.GetNewClosure())
    }
    if ($ui.BtnClearSelection) {
        $ui.BtnClearSelection.Add_Click({
            $ui.CmbPresets.SelectedIndex = 0
            Select-OptiKitPreset -Ui $ui -PresetKey ''
        }.GetNewClosure())
    }

    $Window.Add_PreviewKeyDown({
        param($keySender, $keyArgs)
        if (($keyArgs.Key -eq 'F') -and ([System.Windows.Input.Keyboard]::Modifiers -eq 'Control')) {
            [void]$ui.TxtSearchBox.Focus()
            $ui.TxtSearchBox.SelectAll()
            $keyArgs.Handled = $true
        }
        elseif (($keyArgs.Key -eq 'Escape') -and $ui.TxtSearchBox.IsKeyboardFocused -and $ui.TxtSearchBox.Text) {
            $ui.TxtSearchBox.Text = ''
            $keyArgs.Handled = $true
        }
    }.GetNewClosure())

    return $ui
}

function Show-AppliedChangesDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui
    )

    $lines = New-Object 'System.Collections.Generic.List[string]'
    [void]$lines.Add('Ajustes ativos nesta máquina:')

    $activeCount = 0
    foreach ($tid in $Ui.TweakStatuses.Keys) {
        if ($Ui.TweakStatuses[$tid] -ne 'Applied') { continue }
        $definition = if ($Ui.TweakDefinitionMap) { $Ui.TweakDefinitionMap[$tid] } else { $null }
        if ($definition) {
            [void]$lines.Add(("• [Tweak] {0} ({1})" -f $definition.Config.title, $tid))
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
        [void]$lines.Add('Nenhum ajuste do catálogo está aplicado no momento.')
    }

    [void]$lines.Add('')
    [void]$lines.Add('Registrado para reversão (state.json):')
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
    [void][System.Windows.MessageBox]::Show($Ui.Window, $msg, 'Alterações aplicadas', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
}
