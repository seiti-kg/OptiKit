# Componentes de referência do redesign da UI, validados por render (docs/plans/ui-redesign.md).
# Copiar para src/windows/ui/ui-builder.ps1 nas fases F3/F4. Dependem das chaves Text.* e Brush.* de theme.xaml.

function Get-OptiKitUiResource {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [Parameter(Mandatory = $true)][string]$Key
    )
    return $Ui.Window.FindResource($Key)
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

# Linha selecionável usada por apps, ajustes e otimizações de jogo.
# Linha 1: título (corta com reticências) + estado à direita. Linha 2: descrição + metadados à direita.
# Cada linha é um DockPanel próprio: metadados longos não roubam largura do título.
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

# UniformGrid cujo número de colunas acompanha a largura do host (ver Update-OptiKitResponsiveGrids).
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
            CheckBox       = $cb
            Card           = $cb
            BadgeApplied   = $row.BadgeApplied
            Config         = $tweakVal
            BlockReason    = $blockReason
            SearchText     = $def.SearchText
            Category       = $def.Category
            Impact         = $def.Impact
            Risk           = $def.Risk
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

# Busca: esconde linhas, cabeçalhos de grupo e seções vazias; mostra estado vazio por página.
# Cada grupo em $Ui.SearchGroups: @{ Page = 'Apps'|'Tweaks'|'Games'; Header = <elemento>; Container = <elemento>; Entries = <lista de entradas com .Card e .SearchText> }
function Invoke-SearchFilter {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [AllowEmptyString()][string]$Query
    )

    $q = if ($Query) { $Query.Trim().ToLowerInvariant() } else { '' }
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
        else {
            $emptyTb.Visibility = 'Collapsed'
        }
    }
    return $visibleByPage
}
