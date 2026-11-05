# Preview do redesign: monta as listas com components.ps1 dentro do theme.xaml candidato e salva PNGs (somente leitura, dados sintéticos).
# Uso: powershell -ExecutionPolicy Bypass -File .\docs\plans\ui-redesign\preview.ps1
param(
    [string]$OutDir = (Join-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) 'scratch\ui-redesign\preview'),
    [string]$Size = '1240x850,980x660',
    [string]$Query = 'energia'
)

if (([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') -or ($PSVersionTable.PSEdition -ne 'Desktop')) {
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $proc = Start-Process -FilePath $psExe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -STA -File "{0}" -OutDir "{1}" -Size {2} -Query {3}' -f $PSCommandPath, $OutDir, $Size, $Query) -Wait -PassThru -NoNewWindow
    exit $proc.ExitCode
}

$repo = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$script:OptiKitSkipAutoStart = $true
. (Join-Path $repo 'src\windows\main.ps1')
. (Join-Path $repo 'docs\plans\ui-redesign\components.ps1')

function Save-PreviewPng {
    param($Element, [string]$Path, $Background)
    $w = [int][Math]::Ceiling($Element.ActualWidth); $h = [int][Math]::Ceiling($Element.ActualHeight)
    if ($w -le 0 -or $h -le 0) { return }
    $rtb = $null
    for ($a = 1; ($null -eq $rtb) -and ($a -le 3); $a++) { [GC]::Collect(); [GC]::WaitForPendingFinalizers(); [GC]::Collect(); try { $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32) } catch { if ($a -eq 3) { throw } } }
    $dv = New-Object System.Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $rect = New-Object System.Windows.Rect(0, 0, $w, $h)
    if ($Background) { $dc.DrawRectangle($Background, $null, $rect) }
    $vb = New-Object System.Windows.Media.VisualBrush($Element); $vb.Stretch = 'None'; $vb.AlignmentX = 'Left'; $vb.AlignmentY = 'Top'
    $dc.DrawRectangle($vb, $null, $rect); $dc.Close(); $rtb.Render($dv)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [System.IO.File]::Create($Path); try { $enc.Save($fs) } finally { $fs.Close() }
    $rtb = $null; [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
function Invoke-PreviewDoEvents { param($Window) $Window.UpdateLayout(); $Window.Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::ContextIdle); $Window.UpdateLayout() }

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
Initialize-OptiKitEnvironment -DataRoot (Join-Path $env:TEMP ('optikit_prev_' + [Guid]::NewGuid().ToString('N'))) -DryRun | Out-Null
$configs = Get-OptiKitCatalogConfigs
$hardware = Get-OptiKitHardware
$window = [Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $repo 'docs\plans\ui-redesign\theme.xaml'), [Text.Encoding]::UTF8))

$ui = @{ Window = $window; AppCheckboxes = @{}; TweakCheckboxes = @{}; GameOptCheckboxes = @{}; ResponsiveGrids = @{}; SearchGroups = (New-Object 'System.Collections.Generic.List[object]') }
foreach ($n in 'MainTabControl', 'AppsCategoriesHost', 'TweaksCategoriesHost', 'GameProfilesHost', 'DiagnosticsHost', 'TxtDiagnosticsSummary', 'GridStartupItems', 'CmbPresets', 'CmbDohProvider', 'TxtSelectionCounter', 'TxtHardwareSummary', 'TxtStatusMessage', 'TxtConsoleOutput', 'LogPanel', 'TxtSearchBox', 'TxtAppsEmpty', 'TxtTweaksEmpty', 'TxtGamesEmpty', 'BadgeDryRun', 'BadgeUpdate', 'TxtUpdateBadge', 'CmbTweakSort', 'CmbTweakImpact', 'CmbTweakRisk', 'CmbTweakStatus', 'BtnClearTweakFilters', 'TxtTweakCount') {
    $ui[$n] = $window.FindName($n)
}
$ui.TxtHardwareSummary.Text = Format-OptiKitHardwareSummary -Summary $hardware.Summary

if ($ui.CmbTweakSort) {
    Add-OptiKitComboOption -Combo $ui.CmbTweakSort -Text 'Organizar: categoria' -Value 'Category'
    Add-OptiKitComboOption -Combo $ui.CmbTweakImpact -Text 'Impacto: todos' -Value 'All'
    Add-OptiKitComboOption -Combo $ui.CmbTweakRisk -Text 'Risco: todos' -Value 'All'
    Add-OptiKitComboOption -Combo $ui.CmbTweakStatus -Text 'Estado: todos' -Value 'All'
    $ui.CmbTweakSort.SelectedIndex = 0
    $ui.CmbTweakImpact.SelectedIndex = 0
    $ui.CmbTweakRisk.SelectedIndex = 0
    $ui.CmbTweakStatus.SelectedIndex = 0
}
$ui.TxtTweakCount.Text = ('{0} ajustes' -f @($configs.WinTweaks.PSObject.Properties).Count)

# Apps
$first = $true
foreach ($cat in @('Navegadores', 'Comunicação', 'Jogos & Launchers', 'Runtimes & Utilitários', 'Desenvolvimento')) {
    $items = @($configs.Apps.PSObject.Properties | Where-Object { $_.Value.category -eq $cat })
    if ($items.Count -eq 0) { continue }
    $header = New-OptiKitGroupHeader -Ui $ui -Text $cat -Count $items.Count -First:$first
    $first = $false
    $grid = New-OptiKitResponsiveGrid -Ui $ui -Container 'AppsCategoriesHost' -MinColumnWidth 260
    $entries = New-Object 'System.Collections.Generic.List[object]'
    foreach ($p in $items) {
        $a = $p.Value
        $tip = New-OptiKitToolTipContent -Ui $ui -Title $a.name -Body $a.description -Footer ('winget: {0}' -f $a.winget)
        $row = New-OptiKitItemRow -Ui $ui -Title $a.name -Description $a.description -ToolTipContent $tip -Tag $p.Name
        [void]$grid.Children.Add($row.CheckBox)
        $entry = @{ CheckBox = $row.CheckBox; Card = $row.CheckBox; Config = $a; SearchText = ("{0} {1} {2} {3}" -f $a.name, $a.winget, $a.category, $a.description).ToLowerInvariant() }
        $ui.AppCheckboxes[$p.Name] = $entry
        [void]$entries.Add($entry)
    }
    [void]$ui.AppsCategoriesHost.Children.Add($header)
    [void]$ui.AppsCategoriesHost.Children.Add($grid)
    [void]$ui.SearchGroups.Add(@{ Page = 'Apps'; Header = $header; Container = $grid; Entries = $entries })
}

# Ajustes
$osTag = if ($hardware.IsWin11) { 'Win11' } else { 'Win10' }
$first = $true
$i = 0
foreach ($cat in @('Desempenho & Energia', 'Privacidade & Telemetria', 'Windows Update', 'Interface & Windows 11', 'Remoção de Bloatware (Appx)', 'Avançado')) {
    $items = @($configs.WinTweaks.PSObject.Properties | Where-Object { ($_.Value.category -eq $cat) -and (@($_.Value.osSupport) -contains $osTag) -and ($null -eq $_.Value.minBuild -or $hardware.OsBuild -ge [int]$_.Value.minBuild) })
    if ($items.Count -eq 0) { continue }
    $header = New-OptiKitGroupHeader -Ui $ui -Text $cat -Count $items.Count -First:$first
    $first = $false
    $grid = New-OptiKitResponsiveGrid -Ui $ui -Container 'TweaksCategoriesHost' -MinColumnWidth 560
    $entries = New-Object 'System.Collections.Generic.List[object]'
    foreach ($p in $items) {
        $t = $p.Value
        $block = Test-OptiKitTweakBlocked -Tweak $t -Hardware $hardware
        if ($p.Name -eq 'WPFTweaksUltimatePowerPlan') { $block = 'Bloqueado em Ryzen X3D dual-CCD (simulação do preview).' }
        $footerParts = @((Get-OptiKitImpactLabel -Impact $t.impact))
        $riskInfo = Get-OptiKitRiskLabel -Risk $t.riskLevel
        if ($riskInfo) { $footerParts += $riskInfo.Text }
        if ($t.requiresReboot) { $footerParts += 'Requer reinício' }
        $alert = if ($block) { 'Bloqueado neste hardware: ' + $block } else { $null }
        $tip = New-OptiKitToolTipContent -Ui $ui -Title $t.title -Body $t.description -DetailLabel 'Justificativa técnica' -Detail $t.rationale -Footer ($footerParts -join ' · ') -Alert $alert
        $row = New-OptiKitItemRow -Ui $ui -Title $t.title -Description $t.description -Impact $t.impact -Risk $t.riskLevel -RequiresReboot:([bool]$t.requiresReboot) -BlockReason $block -ToolTipContent $tip -Tag $p.Name
        if (($i % 3) -eq 0) { $row.BadgeApplied.Visibility = 'Visible' }
        if (($i % 4) -eq 1 -and -not $block) { $row.CheckBox.IsChecked = $true }
        $i++
        [void]$grid.Children.Add($row.CheckBox)
        $entry = @{ CheckBox = $row.CheckBox; Card = $row.CheckBox; BadgeApplied = $row.BadgeApplied; Config = $t; BlockReason = $block; SearchText = ("{0} {1} {2} {3}" -f $t.title, $t.description, $t.rationale, $t.category).ToLowerInvariant() }
        $ui.TweakCheckboxes[$p.Name] = $entry
        [void]$entries.Add($entry)
    }
    [void]$ui.TweaksCategoriesHost.Children.Add($header)
    [void]$ui.TweaksCategoriesHost.Children.Add($grid)
    [void]$ui.SearchGroups.Add(@{ Page = 'Tweaks'; Header = $header; Container = $grid; Entries = $entries })
}

# Jogos
$first = $true
$j = 0
foreach ($gp in $configs.GameProfiles.PSObject.Properties) {
    $prof = $gp.Value
    $exe = if ($prof.status -eq 'active') { Find-GameExecutable -ProfileConfig $prof } else { $null }
    if ($gp.Name -ne 'ProfileValorant') { $exe = $null }
    $section = New-OptiKitGameSection -Ui $ui -GameProfile $prof -ExePath $exe -First:$first
    $first = $false
    $entries = New-Object 'System.Collections.Generic.List[object]'
    foreach ($opt in @($prof.optimizations)) {
        $tip = New-OptiKitToolTipContent -Ui $ui -Title $opt.title -Body $opt.description -DetailLabel 'Justificativa técnica' -Detail $opt.rationale -Footer (Get-OptiKitImpactLabel -Impact $opt.impact)
        $row = New-OptiKitItemRow -Ui $ui -Title $opt.title -Description $opt.description -Impact $opt.impact -Risk $opt.riskLevel -ToolTipContent $tip -Tag $opt.id
        if (($j % 2) -eq 0) { $row.BadgeApplied.Visibility = 'Visible' }
        $j++
        [void]$section.Grid.Children.Add($row.CheckBox)
        $entry = @{ CheckBox = $row.CheckBox; Card = $row.CheckBox; BadgeApplied = $row.BadgeApplied; Config = $opt; SearchText = ("{0} {1} {2} {3}" -f $prof.gameName, $opt.title, $opt.description, $opt.rationale).ToLowerInvariant() }
        $ui.GameOptCheckboxes[$opt.id] = $entry
        [void]$entries.Add($entry)
    }
    [void]$ui.GameProfilesHost.Children.Add($section.Panel)
    [void]$ui.SearchGroups.Add(@{ Page = 'Games'; Header = $null; Container = $section.Panel; Entries = $entries })
}

# Diagnostico (sintetico)
$diag = @(
    (New-OptiKitDiagnosticItem -Id 'SynRam' -Title 'Memória RAM (XMP/EXPO)' -Status 'OK' -Summary 'Módulos operando na velocidade nominal.' -Detail 'DIMM 0: 8 GB @ 3200 MT/s (nominal 3200); DIMM 1: 8 GB @ 3200 MT/s (nominal 3200)'),
    (New-OptiKitDiagnosticItem -Id 'SynMonitor' -Title 'Taxa de atualização do monitor' -Status 'Warn' -Summary 'Monitor abaixo da taxa máxima suportada.' -Detail '\\.\DISPLAY1: 2560x1440 @ 60 Hz (máx. 165 Hz)' -ActionText 'Abrir configurações de vídeo avançadas' -ActionUrl 'ms-settings:display-advanced'),
    (New-OptiKitDiagnosticItem -Id 'SynVbs' -Title 'VBS / Integridade da memória (HVCI)' -Status 'Error' -Summary 'VBS/HVCI ativo.' -Detail 'VirtualizationBasedSecurityStatus=2; SecurityServicesRunning=2. HVCI custa de 3% a 7% em jogos CPU-bound.' -ActionText 'Veja o ajuste avançado HVCI em Ajustes do Windows.'),
    (New-OptiKitDiagnosticItem -Id 'SynX3d' -Title 'Driver 3D V-Cache (AMD)' -Status 'Info' -Summary 'CPU sem 3D V-Cache; verificação não aplicável.' -Detail 'Nenhuma ação necessária.'),
    (New-OptiKitDiagnosticItem -Id 'SynGpu' -Title 'Idade do driver de GPU' -Status 'Unknown' -Summary 'Não foi possível ler a data do driver.')
)
$sorted = @($diag | Sort-Object { (Get-OptiKitDiagnosticVisual -Status $_.Status).Order })
for ($k = 0; $k -lt $sorted.Count; $k++) {
    if ($k -gt 0) { $div = New-Object System.Windows.Controls.Border; $div.Style = $window.FindResource('Divider'); [void]$ui.DiagnosticsHost.Children.Add($div) }
    [void]$ui.DiagnosticsHost.Children.Add((New-OptiKitDiagnosticRow -Ui $ui -Item $sorted[$k]))
}
$ui.TxtDiagnosticsSummary.Text = Format-OptiKitDiagnosticsSummary -Items $diag

# Inicializacao (sintetico)
$names = @('RiotClient', 'Steam', 'Discord', 'Spotify', 'OneDrive', 'Docker Desktop', 'AMDNoiseSuppression', 'WallpaperEngine', 'Medal', 'electron.app.Notion')
$ui.GridStartupItems.ItemsSource = @(for ($k = 0; $k -lt $names.Count; $k++) { [pscustomobject]@{ Name = $names[$k]; Command = ('"C:\Program Files\{0}\{0}.exe" --background' -f $names[$k]); Scope = 'Usuário (HKCU Run)'; Enabled = (($k % 2) -eq 0); StatusText = $(if (($k % 2) -eq 0) { 'Ativado' } else { 'Desativado' }) } })
$ui.GridStartupItems.SelectedIndex = 2

# Rodape / combos
$ph = New-Object System.Windows.Controls.ComboBoxItem; $ph.Content = 'Escolher preset'; $ph.Tag = ''; [void]$ui.CmbPresets.Items.Add($ph)
foreach ($pr in $configs.Presets.PSObject.Properties) { $it = New-Object System.Windows.Controls.ComboBoxItem; $it.Content = $pr.Value.name; $it.Tag = $pr.Name; [void]$ui.CmbPresets.Items.Add($it) }
$ui.CmbPresets.SelectedIndex = 1
foreach ($prov in Get-OptiKitDohProviders) { $it = New-Object System.Windows.Controls.ComboBoxItem; $it.Content = $prov.Name; [void]$ui.CmbDohProvider.Items.Add($it) }
$ui.CmbDohProvider.SelectedIndex = 0
$checked = @($ui.TweakCheckboxes.Values | Where-Object { $_.CheckBox.IsChecked }).Count
$ui.TxtSelectionCounter.Text = Format-OptiKitSelectionCount -Count $checked
$ui.TxtStatusMessage.Text = 'Verificação de estado concluída.'
$ui.TxtConsoleOutput.Text = "[21:15:40] [INFO] OptiKit iniciado`r`n[21:15:44] [OK] Verificação de estado concluída.`r`n[21:15:46] [ERROR] Falha ao instalar 'Discord': winget retornou 0x8A15002B."

foreach ($h in 'AppsCategoriesHost', 'TweaksCategoriesHost', 'GameProfilesHost') { Register-OptiKitResponsiveHost -Ui $ui -Container $h }

$window.WindowStartupLocation = 'Manual'; $window.Left = -32000; $window.Top = -32000; $window.ShowInTaskbar = $false; $window.ShowActivated = $false
$window.Show()
foreach ($token in ($Size -split ',')) {
    $wh = $token.Split('x'); $window.Width = [int]$wh[0]; $window.Height = [int]$wh[1]
    Invoke-PreviewDoEvents $window
    $root = [System.Windows.Media.VisualTreeHelper]::GetChild($window, 0)
    for ($t = 0; $t -lt $ui.MainTabControl.Items.Count; $t++) {
        $ui.MainTabControl.SelectedIndex = $t
        Invoke-PreviewDoEvents $window; Invoke-PreviewDoEvents $window
        Save-PreviewPng -Element $root -Path (Join-Path $OutDir ('{0}_tab{1}.png' -f $token, $t))
    }
}
# Log aberto + busca
$window.Width = 1240; $window.Height = 850
$ui.LogPanel.Visibility = 'Visible'
$ui.MainTabControl.SelectedIndex = 1
$ui.TxtSearchBox.Text = $Query
$null = Invoke-SearchFilter -Ui $ui -Query $Query
Invoke-PreviewDoEvents $window; Invoke-PreviewDoEvents $window
Save-PreviewPng -Element ([System.Windows.Media.VisualTreeHelper]::GetChild($window, 0)) -Path (Join-Path $OutDir 'search_log.png')
$ui.LogPanel.Visibility = 'Collapsed'
$ui.TxtSearchBox.Text = 'discord'
$null = Invoke-SearchFilter -Ui $ui -Query 'discord'
Invoke-PreviewDoEvents $window; Invoke-PreviewDoEvents $window
Save-PreviewPng -Element ([System.Windows.Media.VisualTreeHelper]::GetChild($window, 0)) -Path (Join-Path $OutDir 'search_elsewhere.png')
$ui.TxtSearchBox.Text = 'xyzabc'
$null = Invoke-SearchFilter -Ui $ui -Query 'xyzabc'
Invoke-PreviewDoEvents $window; Invoke-PreviewDoEvents $window
Save-PreviewPng -Element ([System.Windows.Media.VisualTreeHelper]::GetChild($window, 0)) -Path (Join-Path $OutDir 'search_empty.png')
$window.Close()
Write-Host "OK $OutDir"
