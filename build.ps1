# Compilador determinístico do OptiKit: empacota src/windows + config/*.json em win.ps1 e gera docs/tweaks.md
[CmdletBinding()]
param(
    [switch]$Docs,
    [switch]$EnsureSourceBom
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
$repoSlug = 'seiti-kg/OptiKit'

function Save-FileUtf8Bom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    $normalized = ($Content -replace "\r?\n", "`r`n")
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $normalized, $utf8Bom)
}

function ConvertTo-AsciiJsonText {
    param([Parameter(Mandatory = $true)][string]$JsonText)
    $sb = New-Object System.Text.StringBuilder($JsonText.Length)
    foreach ($ch in $JsonText.ToCharArray()) {
        $code = [int]$ch
        if ($code -gt 127) {
            [void]$sb.Append(('\u{0:x4}' -f $code))
        }
        else {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString()
}

function ConvertTo-AsciiXamlText {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$XamlText)
    if ([string]::IsNullOrEmpty($XamlText)) { return '' }
    $sb = New-Object System.Text.StringBuilder($XamlText.Length)
    for ($i = 0; $i -lt $XamlText.Length; $i++) {
        $ch = $XamlText[$i]
        $code = [int]$ch
        if ($code -le 127) {
            [void]$sb.Append($ch)
        }
        elseif ([char]::IsHighSurrogate($ch) -and ($i + 1 -lt $XamlText.Length) -and [char]::IsLowSurrogate($XamlText[$i + 1])) {
            $utf32 = [char]::ConvertToUtf32($ch, $XamlText[$i + 1])
            [void]$sb.Append(('&#x{0:X};' -f $utf32))
            $i++
        }
        else {
            [void]$sb.Append(('&#x{0:X4};' -f $code))
        }
    }
    return $sb.ToString()
}

function ConvertTo-AsciiPowerShellCode {
    param([Parameter(Mandatory = $true)][string]$Code)

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Code, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        $errMsg = ($parseErrors | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "Erro de sintaxe ao processar módulo PowerShell:`r`n$errMsg"
    }

    $sb = New-Object System.Text.StringBuilder($Code)
    for ($i = $tokens.Count - 1; $i -ge 0; $i--) {
        $t = $tokens[$i]
        $raw = $t.Text
        $hasNonAscii = $false
        foreach ($ch in $raw.ToCharArray()) {
            if ([int]$ch -gt 127) { $hasNonAscii = $true; break }
        }
        if (-not $hasNonAscii) { continue }

        if ($t.Kind -eq 'Comment') {
            $asciiComment = -join ($raw.ToCharArray() | ForEach-Object {
                if ([int]$_ -gt 127) { '-' } else { $_ }
            })
            [void]$sb.Remove($t.Extent.StartOffset, $t.Extent.EndOffset - $t.Extent.StartOffset)
            [void]$sb.Insert($t.Extent.StartOffset, $asciiComment)
        }
        elseif ($t.Kind -eq 'StringLiteral') {
            $val = $t.Value
            $escaped = New-Object System.Text.StringBuilder '"'
            foreach ($ch in $val.ToCharArray()) {
                $codePt = [int]$ch
                if ($codePt -gt 127) {
                    [void]$escaped.Append(('$([char]0x{0:X4})' -f $codePt))
                }
                elseif ($ch -eq '"' -or $ch -eq '$' -or $ch -eq '`') {
                    [void]$escaped.Append('`').Append($ch)
                }
                else {
                    [void]$escaped.Append($ch)
                }
            }
            [void]$escaped.Append('"')
            [void]$sb.Remove($t.Extent.StartOffset, $t.Extent.EndOffset - $t.Extent.StartOffset)
            [void]$sb.Insert($t.Extent.StartOffset, $escaped.ToString())
        }
        elseif ($t.Kind -eq 'StringExpandable') {
            $converted = -join ($raw.ToCharArray() | ForEach-Object {
                if ([int]$_ -gt 127) { '$([char]0x{0:X4})' -f [int]$_ } else { $_ }
            })
            [void]$sb.Remove($t.Extent.StartOffset, $t.Extent.EndOffset - $t.Extent.StartOffset)
            [void]$sb.Insert($t.Extent.StartOffset, $converted)
        }
    }

    return $sb.ToString()
}

$dirsToBom = @(
    (Join-Path $repoRoot 'config'),
    (Join-Path $repoRoot 'src'),
    (Join-Path $repoRoot 'tests')
) | Where-Object { Test-Path -LiteralPath $_ }
$sourceFiles = Get-ChildItem -Path $dirsToBom -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @('.ps1', '.psd1', '.psm1', '.json', '.xaml') }
foreach ($sf in $sourceFiles) {
    $text = [System.IO.File]::ReadAllText($sf.FullName, [System.Text.Encoding]::UTF8)
    Save-FileUtf8Bom -Path $sf.FullName -Content $text
}
$selfText = [System.IO.File]::ReadAllText($MyInvocation.MyCommand.Path, [System.Text.Encoding]::UTF8)
Save-FileUtf8Bom -Path $MyInvocation.MyCommand.Path -Content $selfText

$versionPath = Join-Path $repoRoot 'VERSION'
$version = ([System.IO.File]::ReadAllText($versionPath, [System.Text.Encoding]::UTF8)).Trim()

$configFiles = @{
    Apps         = Join-Path $repoRoot 'config\apps.json'
    WinTweaks    = Join-Path $repoRoot 'config\win-tweaks.json'
    GameProfiles = Join-Path $repoRoot 'config\game-profiles.json'
    GameLogos    = Join-Path $repoRoot 'config\game-logos.json'
    Presets      = Join-Path $repoRoot 'config\presets.json'
}

$logoPath = Join-Path $repoRoot 'assets\optikit_logo_ui.png'
if (-not (Test-Path -LiteralPath $logoPath)) {
    throw "Logo compacto obrigatório ausente: $logoPath"
}
$logoBase64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($logoPath))

$rawConfigs = @{}
$parsedConfigs = @{}
foreach ($key in $configFiles.Keys) {
    $path = $configFiles[$key]
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Arquivo de configuração obrigatório ausente: $path"
    }
    $content = ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) -replace "\r?\n", "`r`n").Trim()
    if ($content -match '(?m)^''@') {
        throw "O arquivo $path contém uma linha iniciando com '@, o que quebraria o here-string."
    }
    try {
        $parsedConfigs[$key] = $content | ConvertFrom-Json
    }
    catch {
        throw "JSON inválido em ${path}: $($_.Exception.Message)"
    }
    $rawConfigs[$key] = ConvertTo-AsciiJsonText -JsonText $content
}

$xamlPath = Join-Path $repoRoot 'src\windows\ui\theme.xaml'
$asciiXaml = ''
if (Test-Path -LiteralPath $xamlPath) {
    $rawXaml = ([System.IO.File]::ReadAllText($xamlPath, [System.Text.Encoding]::UTF8) -replace "\r?\n", "`r`n").Trim()
    if ($rawXaml -match '(?m)^''@') {
        throw "O arquivo theme.xaml contém uma linha iniciando com '@."
    }
    $asciiXaml = ConvertTo-AsciiXamlText -XamlText $rawXaml
}

$moduleOrder = @(
    'src\windows\core\logger.ps1',
    'src\windows\core\backup.ps1',
    'src\windows\modules\hardware-utils.ps1',
    'src\windows\modules\winget-engine.ps1',
    'src\windows\modules\tweak-engine.ps1',
    'src\windows\modules\game-engine.ps1',
    'src\windows\modules\maintenance.ps1',
    'src\windows\modules\network-engine.ps1',
    'src\windows\modules\startup-manager.ps1',
    'src\windows\core\state-checker.ps1',
    'src\windows\modules\diagnostics.ps1',
    'src\windows\modules\process-tools.ps1',
    'src\windows\modules\uninstall-engine.ps1',
    'src\windows\modules\duplicate-engine.ps1',
    'src\windows\ui\ui-builder.ps1',
    'src\windows\main.ps1'
)

$compiledModules = New-Object 'System.Collections.Generic.List[string]'
foreach ($relPath in $moduleOrder) {
    $fullPath = Join-Path $repoRoot $relPath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Write-Verbose "Módulo ainda não presente (pulando): $relPath"
        continue
    }
    $modContent = [System.IO.File]::ReadAllText($fullPath, [System.Text.Encoding]::UTF8)
    $modContent = $modContent -replace '(?ms)^\s*#region\s+dev-only.*?^\s*#endregion[^\r\n]*\r?\n?', ''
    $modContent = ($modContent -replace "\r?\n", "`r`n").Trim()
    $asciiMod = ConvertTo-AsciiPowerShellCode -Code $modContent
    $banner = "# ============================================================================`r`n# Module: $($relPath -replace '\\', '/')`r`n# ============================================================================"
    [void]$compiledModules.Add("$banner`r`n$asciiMod")
}

$outBuilder = New-Object System.Text.StringBuilder
[void]$outBuilder.AppendLine('# ============================================================================')
[void]$outBuilder.AppendLine("# OptiKit v$version - Multi-OS System & Gaming Optimizer (Windows Build)")
[void]$outBuilder.AppendLine("# Repository: https://github.com/$repoSlug")
[void]$outBuilder.AppendLine("# One-Liner : irm https://raw.githubusercontent.com/$repoSlug/main/win.ps1 | iex")
[void]$outBuilder.AppendLine('# AUTO-GENERATED BY build.ps1 - DO NOT EDIT DIRECTLY')
[void]$outBuilder.AppendLine('# ============================================================================')
[void]$outBuilder.AppendLine('[CmdletBinding()]')
[void]$outBuilder.AppendLine('param(')
[void]$outBuilder.AppendLine('    [switch]$DryRun,')
[void]$outBuilder.AppendLine('    [string]$Preset,')
[void]$outBuilder.AppendLine('    [switch]$SmokeTest,')
[void]$outBuilder.AppendLine('    [switch]$NoElevate,')
[void]$outBuilder.AppendLine('    [switch]$Relaunched,')
[void]$outBuilder.AppendLine('    [switch]$Apply,')
[void]$outBuilder.AppendLine('    [switch]$Silent,')
[void]$outBuilder.AppendLine('    [string]$Config')
[void]$outBuilder.AppendLine(')')
[void]$outBuilder.AppendLine('')
[void]$outBuilder.AppendLine("`$script:OptiKitVersion = '$version'")
[void]$outBuilder.AppendLine("`$script:OptiKitRepo = '$repoSlug'")
[void]$outBuilder.AppendLine("`$script:EmbeddedLogoBase64 = '$logoBase64'")
[void]$outBuilder.AppendLine('')
[void]$outBuilder.AppendLine('$script:EmbeddedAppsJson = @''')
[void]$outBuilder.AppendLine($rawConfigs['Apps'])
[void]$outBuilder.AppendLine('''@')
[void]$outBuilder.AppendLine('')
[void]$outBuilder.AppendLine('$script:EmbeddedWinTweaksJson = @''')
[void]$outBuilder.AppendLine($rawConfigs['WinTweaks'])
[void]$outBuilder.AppendLine('''@')
[void]$outBuilder.AppendLine('')
[void]$outBuilder.AppendLine('$script:EmbeddedGameProfilesJson = @''')
[void]$outBuilder.AppendLine($rawConfigs['GameProfiles'])
[void]$outBuilder.AppendLine('''@')
[void]$outBuilder.AppendLine('')
[void]$outBuilder.AppendLine('$script:EmbeddedGameLogosJson = @''')
[void]$outBuilder.AppendLine($rawConfigs['GameLogos'])
[void]$outBuilder.AppendLine('''@')
[void]$outBuilder.AppendLine('')
[void]$outBuilder.AppendLine('$script:EmbeddedPresetsJson = @''')
[void]$outBuilder.AppendLine($rawConfigs['Presets'])
[void]$outBuilder.AppendLine('''@')
[void]$outBuilder.AppendLine('')
[void]$outBuilder.AppendLine('$script:EmbeddedThemeXaml = @''')
[void]$outBuilder.AppendLine($asciiXaml)
[void]$outBuilder.AppendLine('''@')
[void]$outBuilder.AppendLine('')

foreach ($cm in $compiledModules) {
    [void]$outBuilder.AppendLine($cm)
    [void]$outBuilder.AppendLine('')
}

$finalWinPs1 = ($outBuilder.ToString() -replace "\r?\n", "`r`n").TrimEnd() + "`r`n"
$winPs1Path = Join-Path $repoRoot 'win.ps1'

# Saved without BOM and 100% 7-bit ASCII so both `irm ... | iex` and `powershell -File win.ps1` work on PS 5.1
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($winPs1Path, $finalWinPs1, $utf8NoBom)

$winTokens = $null
$winErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($winPs1Path, [ref]$winTokens, [ref]$winErrors)
if ($winErrors -and $winErrors.Count -gt 0) {
    $errText = ($winErrors | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    throw "Falha de validação de sintaxe no win.ps1 gerado:`r`n$errText"
}

if ($Docs) {
    $docsDir = Join-Path $repoRoot 'docs'
    if (-not (Test-Path -LiteralPath $docsDir)) {
        New-Item -Path $docsDir -ItemType Directory -Force | Out-Null
    }
    $docSb = New-Object System.Text.StringBuilder
    [void]$docSb.AppendLine('# Catálogo Técnico de Otimizações e Pacotes (`OptiKit`)')
    [void]$docSb.AppendLine('')
    [void]$docSb.AppendLine('> Documento gerado automaticamente por `./build.ps1 -Docs` a partir dos arquivos em `config/`.')
    [void]$docSb.AppendLine('')
    [void]$docSb.AppendLine('## 1. Otimizações de Sistema e Debloat (`config/win-tweaks.json`)')
    [void]$docSb.AppendLine('')
    [void]$docSb.AppendLine('| ID | Título | Categoria | Impacto | Risco | SO | Requer Reboot |')
    [void]$docSb.AppendLine('|---|---|---|---|---|---|---|')

    $tweaksObj = $parsedConfigs['WinTweaks']
    foreach ($prop in $tweaksObj.PSObject.Properties) {
        $id = $prop.Name
        $t = $prop.Value
        $os = ($t.osSupport -join ', ')
        $rb = if ($t.requiresReboot) { 'Sim' } else { 'Não' }
        [void]$docSb.AppendLine("| ``$id`` | $($t.title) | $($t.category) | **$($t.impact)** | ``$($t.riskLevel)`` | $os | $rb |")
    }

    [void]$docSb.AppendLine('')
    [void]$docSb.AppendLine('### Detalhamento Técnico e Justificativa (Anti-Placebo)')
    [void]$docSb.AppendLine('')

    foreach ($prop in $tweaksObj.PSObject.Properties) {
        $id = $prop.Name
        $t = $prop.Value
        [void]$docSb.AppendLine("#### $($t.title) (``$id``)")
        [void]$docSb.AppendLine("- **Categoria:** $($t.category) | **Impacto:** $($t.impact) | **Risco:** $($t.riskLevel)")
        if ($t.blockedOn -and @($t.blockedOn).Count -gt 0) {
            [void]$docSb.AppendLine("- **Bloqueado em:** $((@($t.blockedOn)) -join ', ')")
        }
        [void]$docSb.AppendLine("- **Descrição:** $($t.description)")
        [void]$docSb.AppendLine("- **Justificativa Técnica (Rationale):** $($t.rationale)")
        [void]$docSb.AppendLine('')
    }

    [void]$docSb.AppendLine('## 2. Perfis de Jogos (`config/game-profiles.json`)')
    [void]$docSb.AppendLine('')
    $gamesObj = $parsedConfigs['GameProfiles']
    foreach ($gProp in $gamesObj.PSObject.Properties) {
        $g = $gProp.Value
        [void]$docSb.AppendLine("### $($g.gameName) (``$($gProp.Name)``)")
        [void]$docSb.AppendLine("- **Engine:** $($g.engine) | **Anti-Cheat:** $($g.antiCheat)")
        [void]$docSb.AppendLine("- **Aviso:** $($g.warning)")
        if ($g.optimizations -and $g.optimizations.Count -gt 0) {
            [void]$docSb.AppendLine('')
            [void]$docSb.AppendLine('| ID | Otimização | Action | Impacto | Justificativa |')
            [void]$docSb.AppendLine('|---|---|---|---|---|')
            foreach ($opt in $g.optimizations) {
                [void]$docSb.AppendLine("| ``$($opt.id)`` | $($opt.title) | ``$($opt.action)`` | **$($opt.impact)** | $($opt.rationale) |")
            }
        }
        [void]$docSb.AppendLine('')
    }

    [void]$docSb.AppendLine('## 3. Catálogo de Aplicativos (`config/apps.json`)')
    [void]$docSb.AppendLine('')
    [void]$docSb.AppendLine('| ID | Nome | Categoria | Winget ID | Flatpak ID |')
    [void]$docSb.AppendLine('|---|---|---|---|---|')
    $appsObj = $parsedConfigs['Apps']
    foreach ($aProp in $appsObj.PSObject.Properties) {
        $a = $aProp.Value
        $wg = if ($a.winget) { "``$($a.winget)``" } else { '-' }
        $fp = if ($a.flatpak) { "``$($a.flatpak)``" } else { '-' }
        [void]$docSb.AppendLine("| ``$($aProp.Name)`` | $($a.name) | $($a.category) | $wg | $fp |")
    }

    $docsFile = Join-Path $docsDir 'tweaks.md'
    $normalizedDocs = ($docSb.ToString() -replace "\r?\n", "`n"); [System.IO.File]::WriteAllText($docsFile, $normalizedDocs, (New-Object System.Text.UTF8Encoding($false)))
}
