# Trava de regressão visual: roda tools/ui-audit.ps1 com dados sintéticos e confere as metas do redesign

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    $outDir = Join-Path $TestDrive 'ui-audit'
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $psExe -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $script:RepoRoot 'tools\ui-audit.ps1') -NoPng -OutDir $outDir | Out-Null
    $script:ExitCode = $LASTEXITCODE
    $script:Report = Get-Content -LiteralPath (Join-Path $outDir 'report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
}

Describe 'Auditoria de layout da GUI (tools/ui-audit.ps1)' {
    It 'Deve renderizar todas as páginas sem erro' {
        $script:ExitCode | Should -Be 0
    }

    It 'Deve usar somente a escala tipográfica 12/14/16/20' {
        @($script:Report.FontSizes | Where-Object { $_ -notin @(12, 14, 16, 20) }) | Should -BeNullOrEmpty
    }

    It 'Deve usar somente cores da paleta definida no theme.xaml' {
        $script:Report.OffPalette | Should -BeNullOrEmpty
    }

    It 'Não deve usar emoji como ícone' {
        $script:Report.EmojiTexts | Should -BeNullOrEmpty
    }

    It 'Não deve cortar controles fixos em nenhum tamanho' {
        $script:Report.OutOfBounds | Should -BeNullOrEmpty
    }

    It 'Deve manter Aplicar visível nas páginas de lista e oculto nas demais' {
        foreach ($size in $script:Report.Sizes) {
            foreach ($tab in $size.Tabs) {
                $expected = if ($tab.Index -le 2) { 'visivel' } else { 'oculto' }
                $tab.PrimaryAction | Should -Be $expected -Because ("{0}, página {1}" -f $size.Size, $tab.Index)
            }
        }
    }

    It 'Deve dar altura útil à tabela de inicialização no tamanho mínimo' {
        $minSize = $script:Report.Sizes | Where-Object { $_.Size -eq '980x660' }
        $startup = $minSize.Tabs | Where-Object { $null -ne $_.StartupGridHeight }
        $startup.StartupGridHeight | Should -BeGreaterOrEqual 300
    }

    It 'Não deve usar mais de 4 contornos autorais por página' {
        foreach ($size in $script:Report.Sizes) {
            foreach ($tab in $size.Tabs) {
                $tab.AuthoredBorders | Should -BeLessOrEqual 4 -Because ("{0}, página {1}" -f $size.Size, $tab.Index)
            }
        }
    }
}
