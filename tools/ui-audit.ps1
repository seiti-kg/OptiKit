# Ferramenta de desenvolvimento: renderiza a GUI WPF do OptiKit fora da tela, mede o layout de cada aba e salva PNGs.
# Somente leitura: nenhum ajuste é aplicado no sistema. Por padrão usa dados sintéticos (determinístico e rápido).
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File .\tools\ui-audit.ps1
#   powershell -ExecutionPolicy Bypass -File .\tools\ui-audit.ps1 -Data Real -Size 1240x850
#   powershell -ExecutionPolicy Bypass -File .\tools\ui-audit.ps1 -UseBuild -NoPng -OutDir .\scratch\audit
#   powershell -ExecutionPolicy Bypass -File .\tools\ui-audit.ps1 -ThemePath .\docs\plans\ui-redesign\theme.xaml
[CmdletBinding()]
param(
    [string]$OutDir,
    [string]$Size = '1240x850,980x660',
    [ValidateSet('Synthetic', 'Real')]
    [string]$Data = 'Synthetic',
    [string]$ThemePath,
    [switch]$UseBuild,
    [switch]$NoPng
)

$repoRoot = Split-Path -Path $PSScriptRoot -Parent

if (([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') -or ($PSVersionTable.PSEdition -ne 'Desktop')) {
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argList = New-Object 'System.Collections.Generic.List[string]'
    foreach ($a in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', ('"{0}"' -f $PSCommandPath), '-Size', $Size, '-Data', $Data)) {
        [void]$argList.Add($a)
    }
    if ($OutDir) { [void]$argList.Add('-OutDir'); [void]$argList.Add(('"{0}"' -f $OutDir)) }
    if ($ThemePath) { [void]$argList.Add('-ThemePath'); [void]$argList.Add(('"{0}"' -f $ThemePath)) }
    if ($UseBuild) { [void]$argList.Add('-UseBuild') }
    if ($NoPng) { [void]$argList.Add('-NoPng') }
    $proc = Start-Process -FilePath $psExe -ArgumentList ($argList -join ' ') -Wait -PassThru -NoNewWindow
    exit $proc.ExitCode
}

$script:EmojiPattern = '[\u2190-\u21FF\u2300-\u23FF\u2460-\u27BF\u2900-\u297F\u2B00-\u2BFF\uFE0F]|[\uD83C-\uD83E][\uDC00-\uDFFF]'
$script:IconFontPattern = '(?i)Segoe (Fluent Icons|MDL2 Assets)'
$script:SkipTextNames = @('TxtConsoleOutput', 'TxtSearchBox')

function Invoke-UiAuditDoEvents {
    param([Parameter(Mandatory = $true)][System.Windows.Window]$Window)
    $Window.UpdateLayout()
    $Window.Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::ContextIdle)
    $Window.UpdateLayout()
}

function Get-UiAuditNodes {
    param([Parameter(Mandatory = $true)][System.Windows.DependencyObject]$Root)
    $result = New-Object 'System.Collections.Generic.List[System.Windows.DependencyObject]'
    $stack = New-Object 'System.Collections.Generic.Stack[System.Windows.DependencyObject]'
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $node = $stack.Pop()
        if (($node -is [System.Windows.UIElement]) -and (-not $node.IsVisible)) { continue }
        if (($node -is [System.Windows.FrameworkElement]) -and (($node.ActualWidth -lt 0.5) -or ($node.ActualHeight -lt 0.5))) { continue }
        $result.Add($node)
        if (($node -isnot [System.Windows.Media.Visual]) -and ($node -isnot [System.Windows.Media.Media3D.Visual3D])) { continue }
        $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($node)
        for ($i = $count - 1; $i -ge 0; $i--) {
            $stack.Push([System.Windows.Media.VisualTreeHelper]::GetChild($node, $i))
        }
    }
    return , $result
}

function Get-UiAuditBrushColor {
    param($Brush)
    if (($Brush -is [System.Windows.Media.SolidColorBrush]) -and ($Brush.Color.A -gt 0) -and ($Brush.Opacity -gt 0)) {
        return $Brush.Color.ToString()
    }
    return $null
}

function Get-UiAuditLabel {
    param([Parameter(Mandatory = $true)]$Element)
    if ($Element.Name) { return [string]$Element.Name }
    $text = $null
    if ($Element -is [System.Windows.Controls.ContentControl]) {
        if ($Element.Content -is [string]) { $text = $Element.Content }
        elseif ($Element.Content -is [System.Windows.Controls.TextBlock]) { $text = $Element.Content.Text }
    }
    if ($text) { return ("{0} '{1}'" -f $Element.GetType().Name, $text) }
    return $Element.GetType().Name
}

function Get-UiAuditOrigin {
    param([Parameter(Mandatory = $true)]$Element)
    $type = $Element.GetType().Name
    $node = $Element
    while ($node) {
        if (($node -is [System.Windows.FrameworkElement]) -and $node.Name) { return ('{0} em {1}' -f $type, $node.Name) }
        $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
    }
    return $type
}

function Add-UiAuditColor {
    param(
        [Parameter(Mandatory = $true)]$Set,
        [Parameter(Mandatory = $true)][hashtable]$Totals,
        [Parameter(Mandatory = $true)][string]$Color,
        [Parameter(Mandatory = $true)]$Element
    )
    [void]$Set.Add($Color)
    if (-not $Totals.ColorWhere.ContainsKey($Color)) {
        $Totals.ColorWhere[$Color] = New-Object 'System.Collections.Generic.HashSet[string]'
    }
    if ($Totals.ColorWhere[$Color].Count -lt 3) {
        [void]$Totals.ColorWhere[$Color].Add((Get-UiAuditOrigin -Element $Element))
    }
}

function Get-UiAuditText {
    param([Parameter(Mandatory = $true)][System.Windows.Controls.TextBlock]$TextBlock)
    if (-not [string]::IsNullOrEmpty($TextBlock.Text)) { return $TextBlock.Text }
    if ($TextBlock.Inlines.Count -gt 0) {
        return (New-Object System.Windows.Documents.TextRange($TextBlock.ContentStart, $TextBlock.ContentEnd)).Text
    }
    return ''
}

function Test-UiAuditInsideScrollViewer {
    param([Parameter(Mandatory = $true)]$Element, [Parameter(Mandatory = $true)]$Root)
    $parent = [System.Windows.Media.VisualTreeHelper]::GetParent($Element)
    while ($parent -and ($parent -ne $Root)) {
        if (($parent -is [System.Windows.Controls.ScrollViewer]) -and ($null -eq $parent.TemplatedParent)) { return $true }
        $parent = [System.Windows.Media.VisualTreeHelper]::GetParent($parent)
    }
    return $false
}

function Test-UiAuditOutOfBounds {
    param([Parameter(Mandatory = $true)]$Element, [Parameter(Mandatory = $true)]$Root)
    try {
        $rect = New-Object System.Windows.Rect(0, 0, $Element.ActualWidth, $Element.ActualHeight)
        $bounds = $Element.TransformToAncestor($Root).TransformBounds($rect)
    }
    catch {
        return $false
    }
    return (($bounds.Left -lt -0.5) -or ($bounds.Top -lt -0.5) -or ($bounds.Right -gt ($Root.ActualWidth + 0.5)) -or ($bounds.Bottom -gt ($Root.ActualHeight + 0.5)))
}

function Save-UiAuditPng {
    param(
        [Parameter(Mandatory = $true)]$Element,
        [Parameter(Mandatory = $true)][string]$Path,
        $Background
    )
    $w = [int][Math]::Ceiling($Element.ActualWidth)
    $h = [int][Math]::Ceiling($Element.ActualHeight)
    if (($w -le 0) -or ($h -le 0)) { return }
    # RenderTargetBitmap retém memória não gerenciada até a finalização; sem coletar antes, capturas seguidas estouram memória.
    $rtb = $null
    for ($attempt = 1; ($null -eq $rtb) -and ($attempt -le 3); $attempt++) {
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        [GC]::Collect()
        try {
            $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
        }
        catch {
            if ($attempt -eq 3) { throw }
        }
    }
    $dv = New-Object System.Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $rect = New-Object System.Windows.Rect(0, 0, $w, $h)
    if ($Background) { $dc.DrawRectangle($Background, $null, $rect) }
    $vb = New-Object System.Windows.Media.VisualBrush($Element)
    $vb.Stretch = 'None'
    $vb.AlignmentX = 'Left'
    $vb.AlignmentY = 'Top'
    $dc.DrawRectangle($vb, $null, $rect)
    $dc.Close()
    $rtb.Render($dv)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [System.IO.File]::Create($Path)
    try { $enc.Save($fs) } finally { $fs.Close() }
}

function Set-UiAuditData {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Ui,
        [Parameter(Mandatory = $true)][hashtable]$Configs,
        [Parameter(Mandatory = $true)][string]$Mode
    )

    if ($Mode -eq 'Real') {
        $state = Get-AllTweaksState -TweaksConfig $Configs.WinTweaks -GameProfilesConfig $Configs.GameProfiles
        $diag = @(Get-OptiKitHardwareDiagnostics)
        $startup = @(Get-OptiKitStartupItems)
    }
    else {
        $tweakStates = @{}
        $i = 0
        foreach ($prop in $Configs.WinTweaks.PSObject.Properties) {
            $tweakStates[$prop.Name] = if (($i % 3) -eq 0) { 'Applied' } else { 'NotApplied' }
            $i++
        }
        $gameStates = @{}
        $j = 0
        foreach ($gp in $Configs.GameProfiles.PSObject.Properties) {
            foreach ($opt in @($gp.Value.optimizations)) {
                $gameStates[$opt.id] = (($j % 2) -eq 0)
                $j++
            }
        }
        $state = [pscustomobject]@{ Tweaks = $tweakStates; GameOpts = $gameStates; CapturedState = @{} }

        $diag = @(
            (New-OptiKitDiagnosticItem -Id 'SynRam' -Title 'Memória RAM (XMP/EXPO)' -Status 'OK' -Summary 'Módulos operando na velocidade nominal.' -Detail 'DIMM 0: 8 GB @ 3200 MT/s (nominal 3200); DIMM 1: 8 GB @ 3200 MT/s (nominal 3200)'),
            (New-OptiKitDiagnosticItem -Id 'SynMonitor' -Title 'Taxa de atualização do monitor' -Status 'Warn' -Summary 'Monitor abaixo da taxa máxima suportada.' -Detail '\\.\DISPLAY1: 2560x1440 @ 60 Hz (máx. 165 Hz)' -ActionText 'Abrir configurações de vídeo avançadas' -ActionUrl 'ms-settings:display-advanced'),
            (New-OptiKitDiagnosticItem -Id 'SynVbs' -Title 'VBS / Integridade da memória (HVCI)' -Status 'Error' -Summary 'VBS/HVCI ativo.' -Detail 'VirtualizationBasedSecurityStatus=2; SecurityServicesRunning=2. HVCI custa de 3% a 7% em jogos CPU-bound.' -ActionText 'Ver ajuste avançado HVCI'),
            (New-OptiKitDiagnosticItem -Id 'SynX3d' -Title 'Driver 3D V-Cache (AMD)' -Status 'Info' -Summary 'CPU sem 3D V-Cache; verificação não aplicável.' -Detail 'Nenhuma ação necessária.'),
            (New-OptiKitDiagnosticItem -Id 'SynGpu' -Title 'Idade do driver de GPU' -Status 'Unknown' -Summary 'Não foi possível ler a data do driver.' -Detail '')
        )

        $startup = New-Object 'System.Collections.Generic.List[pscustomobject]'
        $names = @('RiotClient', 'Steam', 'Discord', 'Spotify', 'OneDrive', 'Docker Desktop', 'AMDNoiseSuppression', 'WallpaperEngine', 'Medal', 'electron.app.Notion', 'SecurityHealth', 'RtkAudUService')
        for ($k = 0; $k -lt $names.Count; $k++) {
            $enabled = (($k % 2) -eq 0)
            [void]$startup.Add([pscustomobject]@{
                Name         = $names[$k]
                Command      = ('"C:\Program Files\{0}\{0}.exe" --background --minimized' -f $names[$k])
                Scope        = if (($k % 3) -eq 0) { 'Sistema (HKLM Run)' } else { 'Usuário (HKCU Run)' }
                ApprovedPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
                Enabled      = $enabled
                StatusText   = if ($enabled) { 'Ativado' } else { 'Desativado' }
                IsProtected  = $false
            })
        }
        $startup = $startup.ToArray()
    }

    Update-OptiKitStateBadges -Ui $Ui -StateReport $state
    Update-OptiKitDiagnosticsUi -Ui $Ui -Items @($diag)
    if ($Ui.GridStartupItems) { $Ui.GridStartupItems.ItemsSource = @($startup) }
    if ($Ui.CmbBenchmarkProcess) {
        [void]$Ui.CmbBenchmarkProcess.Items.Add('game.exe')
        $Ui.CmbBenchmarkProcess.SelectedIndex = 0
    }
    if ($Ui.GridBenchmarkResults) {
        $Ui.GridBenchmarkResults.ItemsSource = @(
            [pscustomobject]@{ Metric = 'FPS médio'; Current = '144.2'; Previous = '138.9'; Delta = '+5.3' },
            [pscustomobject]@{ Metric = '1% low'; Current = '112.4'; Previous = '105.1'; Delta = '+7.3' }
        )
    }
    if ($Ui.TxtBenchmarkStatus) { $Ui.TxtBenchmarkStatus.Text = 'Captura concluída: 3600 frames em 30.0 s.' }
    if ($Ui.CmbPresets -and ($Ui.CmbPresets.Items.Count -gt 1)) { $Ui.CmbPresets.SelectedIndex = 1 }
    if ($Ui.TxtConsoleOutput) {
        $lines = @(
            '[21:15:40] [INFO] OptiKit iniciado (AMD Ryzen 5 5600 | AMD Radeon RX 9060 XT | Desktop | Windows 11 (Build 26200))',
            '[21:15:41] [INFO] Verificando estado atual dos ajustes na máquina...',
            '[21:15:44] [OK] Verificação de estado concluída.',
            '[21:15:45] [WARN] Tweak ''WPFTweaksUltimatePowerPlan'' ignorado no preset: bloqueado em Ryzen X3D dual-CCD.',
            '[21:15:46] [ERROR] Falha ao instalar ''Discord'': winget retornou 0x8A15002B.'
        )
        $Ui.TxtConsoleOutput.Text = ($lines -join [Environment]::NewLine)
    }
    if ($Ui.TxtStatusMessage) { $Ui.TxtStatusMessage.Text = 'Pronto. Selecione um preset ou marque os itens desejados.' }
    return @($diag).Count
}

function Measure-UiAuditTab {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Window]$Window,
        [Parameter(Mandatory = $true)]$Root,
        [Parameter(Mandatory = $true)][hashtable]$Totals
    )

    $nodes = Get-UiAuditNodes -Root $Root
    $fontSizes = New-Object 'System.Collections.Generic.HashSet[double]'
    $colors = New-Object 'System.Collections.Generic.HashSet[string]'
    $outOfBounds = New-Object 'System.Collections.Generic.List[string]'
    $textCount = 0
    $authoredBorders = 0
    $scrollContent = $null

    foreach ($node in $nodes) {
        if ($node -is [System.Windows.Controls.TextBlock]) {
            $text = Get-UiAuditText -TextBlock $node
            if ([string]::IsNullOrWhiteSpace($text)) { continue }
            $textCount++
            $family = [string]$node.FontFamily.Source
            [void]$Totals.FontFamilies.Add($family)
            $color = Get-UiAuditBrushColor -Brush $node.Foreground
            if ($color) { Add-UiAuditColor -Set $colors -Totals $Totals -Color $color -Element $node }
            if ($family -notmatch $script:IconFontPattern) {
                [void]$fontSizes.Add([Math]::Round($node.FontSize, 1))
                if ($text -match $script:EmojiPattern) {
                    $snippet = if ($text.Length -gt 60) { $text.Substring(0, 60) + '...' } else { $text }
                    [void]$Totals.EmojiTexts.Add($snippet.Trim())
                }
            }
            continue
        }
        if ($node -is [System.Windows.Controls.TextBox]) {
            $color = Get-UiAuditBrushColor -Brush $node.Foreground
            if ($color) { Add-UiAuditColor -Set $colors -Totals $Totals -Color $color -Element $node }
        }
        if ($node -is [System.Windows.Controls.Border]) {
            $bg = Get-UiAuditBrushColor -Brush $node.Background
            $bd = Get-UiAuditBrushColor -Brush $node.BorderBrush
            if ($bg) { Add-UiAuditColor -Set $colors -Totals $Totals -Color $bg -Element $node }
            $th = $node.BorderThickness
            $hasStroke = ($bd -and (($th.Left + $th.Top + $th.Right + $th.Bottom) -gt 0))
            if ($hasStroke) { Add-UiAuditColor -Set $colors -Totals $Totals -Color $bd -Element $node }
            if ($hasStroke -and ($null -eq $node.TemplatedParent)) { $authoredBorders++ }
        }
        elseif ($node -is [System.Windows.Controls.Panel]) {
            $bg = Get-UiAuditBrushColor -Brush $node.Background
            if ($bg) { Add-UiAuditColor -Set $colors -Totals $Totals -Color $bg -Element $node }
        }
        elseif ($node -is [System.Windows.Shapes.Shape]) {
            foreach ($b in @($node.Fill, $node.Stroke)) {
                $c = Get-UiAuditBrushColor -Brush $b
                if ($c) { Add-UiAuditColor -Set $colors -Totals $Totals -Color $c -Element $node }
            }
        }

        if (($node -is [System.Windows.Controls.Primitives.ButtonBase]) -or ($node -is [System.Windows.Controls.ComboBox]) -or ($node -is [System.Windows.Controls.TextBox])) {
            if (($null -eq $node.TemplatedParent) -and (-not (Test-UiAuditInsideScrollViewer -Element $node -Root $Root))) {
                if (Test-UiAuditOutOfBounds -Element $node -Root $Root) {
                    [void]$outOfBounds.Add((Get-UiAuditLabel -Element $node))
                }
            }
        }

        if (($null -eq $scrollContent) -and ($node -is [System.Windows.Controls.ScrollViewer]) -and ($null -eq $node.TemplatedParent) -and ($node.Content -is [System.Windows.FrameworkElement])) {
            $scrollContent = $node.Content
        }
    }

    foreach ($c in $colors) { [void]$Totals.Colors.Add($c) }
    foreach ($f in $fontSizes) { [void]$Totals.FontSizes.Add($f) }
    foreach ($o in $outOfBounds) { [void]$Totals.OutOfBounds.Add($o) }

    $primary = $Window.FindName('BtnApplySelected')
    $primaryState = 'ausente'
    if ($primary) {
        if (-not $primary.IsVisible) { $primaryState = 'oculto' }
        elseif (Test-UiAuditOutOfBounds -Element $primary -Root $Root) { $primaryState = 'cortado' }
        else { $primaryState = 'visivel' }
    }

    $startupGrid = $Window.FindName('GridStartupItems')
    $startupHeight = $null
    if ($startupGrid -and $startupGrid.IsVisible) { $startupHeight = [Math]::Round($startupGrid.ActualHeight, 0) }

    return [pscustomobject]@{
        TextBlocks        = $textCount
        AuthoredBorders   = $authoredBorders
        FontSizes         = @($fontSizes | Sort-Object)
        ColorCount        = $colors.Count
        OutOfBounds       = @($outOfBounds | Sort-Object -Unique)
        PrimaryAction     = $primaryState
        StartupGridHeight = $startupHeight
        ScrollHeight      = if ($scrollContent) { [Math]::Round($scrollContent.ActualHeight, 0) } else { $null }
        ScrollContent     = $scrollContent
    }
}

$exitCode = 0
$window = $null
$dataRoot = Join-Path $env:TEMP ('optikit_ui_audit_' + [Guid]::NewGuid().ToString('N'))
try {
    if (-not $OutDir) {
        $OutDir = Join-Path $env:TEMP ('optikit-ui-audit\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }
    if (-not (Test-Path -LiteralPath $OutDir)) {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }
    $OutDir = (Resolve-Path -LiteralPath $OutDir).Path

    $sizes = foreach ($token in ($Size -split ',')) {
        if ($token.Trim() -notmatch '^(\d+)x(\d+)$') { throw "Tamanho inválido: '$token' (use LARGURAxALTURA)." }
        [pscustomobject]@{ Label = $token.Trim(); Width = [int]$Matches[1]; Height = [int]$Matches[2] }
    }

    $script:OptiKitSkipAutoStart = $true
    if ($UseBuild) {
        . (Join-Path $repoRoot 'win.ps1')
    }
    else {
        . (Join-Path $repoRoot 'src\windows\main.ps1')
    }

    Initialize-OptiKitEnvironment -DataRoot $dataRoot -DryRun | Out-Null
    $configs = Get-OptiKitCatalogConfigs
    if ($ThemePath) {
        $configs.ThemeXaml = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $ThemePath).Path, [System.Text.Encoding]::UTF8)
    }
    $hardware = Get-OptiKitHardware
    $window = [Windows.Markup.XamlReader]::Parse($configs.ThemeXaml)
    $ui = Initialize-OptiKitUi -Window $window -Configs $configs -Hardware $hardware
    if ($ui.BadgeDryRun) { $ui.BadgeDryRun.Visibility = 'Collapsed' }
    $diagCount = Set-UiAuditData -Ui $ui -Configs $configs -Mode $Data

    $tokens = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($key in $window.Resources.Keys) {
        $res = $window.Resources[$key]
        if ($res -is [System.Windows.Media.SolidColorBrush]) { [void]$tokens.Add($res.Color.ToString()) }
        elseif ($res -is [System.Windows.Media.Color]) { [void]$tokens.Add($res.ToString()) }
    }

    $tabControl = $window.FindName('MainTabControl')
    if (-not $tabControl) { throw "Controle 'MainTabControl' não encontrado no XAML." }

    $window.WindowStartupLocation = 'Manual'
    $window.Left = -32000
    $window.Top = -32000
    $window.ShowInTaskbar = $false
    $window.ShowActivated = $false
    $window.Show()

    $totals = @{
        FontSizes    = New-Object 'System.Collections.Generic.HashSet[double]'
        FontFamilies = New-Object 'System.Collections.Generic.HashSet[string]'
        Colors       = New-Object 'System.Collections.Generic.HashSet[string]'
        EmojiTexts   = New-Object 'System.Collections.Generic.HashSet[string]'
        OutOfBounds  = New-Object 'System.Collections.Generic.HashSet[string]'
        ColorWhere   = @{}
    }
    $sizeReports = New-Object 'System.Collections.Generic.List[pscustomobject]'

    foreach ($sz in $sizes) {
        $window.Width = $sz.Width
        $window.Height = $sz.Height
        Invoke-UiAuditDoEvents -Window $window
        $root = [System.Windows.Media.VisualTreeHelper]::GetChild($window, 0)
        $tabReports = New-Object 'System.Collections.Generic.List[pscustomobject]'

        for ($t = 0; $t -lt $tabControl.Items.Count; $t++) {
            $tabControl.SelectedIndex = $t
            Invoke-UiAuditDoEvents -Window $window
            $header = [string]$tabControl.Items[$t].Header
            $m = Measure-UiAuditTab -Window $window -Root $root -Totals $totals

            if (-not $NoPng) {
                Save-UiAuditPng -Element $root -Path (Join-Path $OutDir ('{0}_tab{1}.png' -f $sz.Label, $t))
                if ($m.ScrollContent) {
                    Save-UiAuditPng -Element $m.ScrollContent -Path (Join-Path $OutDir ('{0}_tab{1}_full.png' -f $sz.Label, $t)) -Background $window.Background
                }
            }

            [void]$tabReports.Add([pscustomobject]@{
                Index             = $t
                Header            = $header
                TextBlocks        = $m.TextBlocks
                AuthoredBorders   = $m.AuthoredBorders
                FontSizes         = $m.FontSizes
                ColorCount        = $m.ColorCount
                OutOfBounds       = $m.OutOfBounds
                PrimaryAction     = $m.PrimaryAction
                StartupGridHeight = $m.StartupGridHeight
                ScrollHeight      = $m.ScrollHeight
            })
        }
        [void]$sizeReports.Add([pscustomobject]@{ Size = $sz.Label; Tabs = $tabReports.ToArray() })
    }

    $offPalette = @($totals.Colors | Where-Object { -not $tokens.Contains($_) } | Sort-Object)
    $offPaletteWhere = [ordered]@{}
    foreach ($c in $offPalette) { $offPaletteWhere[$c] = @($totals.ColorWhere[$c] | Sort-Object) }
    $report = [pscustomobject]@{
        GeneratedAt     = (Get-Date).ToString('s')
        Source          = if ($UseBuild) { 'win.ps1' } else { 'src/windows/main.ps1' }
        Theme           = if ($ThemePath) { $ThemePath } else { 'src/windows/ui/theme.xaml' }
        Data            = $Data
        Hardware        = $hardware.Summary
        Counts          = [pscustomobject]@{
            Apps        = $ui.AppCheckboxes.Count
            Tweaks      = $ui.TweakCheckboxes.Count
            GameOpts    = $ui.GameOptCheckboxes.Count
            Diagnostics = $diagCount
        }
        PaletteTokens   = @($tokens | Sort-Object)
        FontSizes       = @($totals.FontSizes | Sort-Object)
        FontFamilies    = @($totals.FontFamilies | Sort-Object)
        Colors          = @($totals.Colors | Sort-Object)
        OffPalette      = $offPalette
        OffPaletteWhere = [pscustomobject]$offPaletteWhere
        EmojiTexts      = @($totals.EmojiTexts | Sort-Object)
        OutOfBounds     = @($totals.OutOfBounds | Sort-Object)
        Sizes           = $sizeReports.ToArray()
    }
    $reportPath = Join-Path $OutDir 'report.json'
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 6), $utf8NoBom)

    $inv = [Globalization.CultureInfo]::InvariantCulture
    Write-Host ("UI audit ({0}, dados {1})" -f $report.Source, $Data)
    Write-Host ("  Tamanhos de fonte : {0}" -f (($report.FontSizes | ForEach-Object { $_.ToString($inv) }) -join ' '))
    Write-Host ("  Famílias de fonte : {0}" -f ($report.FontFamilies -join ', '))
    Write-Host ("  Cores (total/fora): {0} / {1}" -f $report.Colors.Count, $offPalette.Count)
    Write-Host ("  Textos com emoji  : {0}" -f $report.EmojiTexts.Count)
    Write-Host ("  Fora da janela    : {0}" -f (@($report.OutOfBounds) -join '; '))
    foreach ($sr in $report.Sizes) {
        foreach ($tr in $sr.Tabs) {
            $tabSizes = ($tr.FontSizes | ForEach-Object { $_.ToString($inv) }) -join ' '
            Write-Host ("  [{0}] aba {1} '{2}': {3} textos, {4} bordas autorais, fontes [{5}], primário {6}, grade inicialização {7}, rolagem {8}" -f $sr.Size, $tr.Index, $tr.Header, $tr.TextBlocks, $tr.AuthoredBorders, $tabSizes, $tr.PrimaryAction, $tr.StartupGridHeight, $tr.ScrollHeight)
        }
    }
    Write-Host ("Relatório: {0}" -f $reportPath)
}
catch {
    Write-Host ("Falha no UI audit: {0}" -f $_.Exception.Message)
    Write-Host $_.ScriptStackTrace
    $exitCode = 1
}
finally {
    if ($window) {
        try { $window.Close() } catch { Write-Verbose $_.Exception.Message }
    }
    Remove-Item -LiteralPath $dataRoot -Recurse -Force -ErrorAction SilentlyContinue
}
exit $exitCode
