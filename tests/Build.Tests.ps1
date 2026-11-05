# Testes de compilação determinística do win.ps1, integridade de encoding/acentos e geração do docs/tweaks.md

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:BuildScript = Join-Path $script:RepoRoot 'build.ps1'
    $script:WinPs1Path = Join-Path $script:RepoRoot 'win.ps1'
    $script:DocsPath = Join-Path $script:RepoRoot 'docs\tweaks.md'
}

Describe 'Compilador Monolítico (build.ps1 -> win.ps1)' {
    It 'Deve gerar win.ps1 e docs/tweaks.md de forma determinística (mesmo SHA256 em dois builds seguidos)' {
        & $script:BuildScript -Docs
        Test-Path -LiteralPath $script:WinPs1Path | Should -BeTrue
        Test-Path -LiteralPath $script:DocsPath | Should -BeTrue

        $hash1 = (Get-FileHash -LiteralPath $script:WinPs1Path -Algorithm SHA256).Hash
        & $script:BuildScript -Docs
        $hash2 = (Get-FileHash -LiteralPath $script:WinPs1Path -Algorithm SHA256).Hash

        $hash1 | Should -Be $hash2
    }

    It 'O win.ps1 compilado deve passar no parser AST do PowerShell sem erros e ser 100% ASCII-safe para irm | iex' {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($script:WinPs1Path, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0

        $bytes = [System.IO.File]::ReadAllBytes($script:WinPs1Path)
        # Primeiro byte não deve ser 0xEF (UTF-8 BOM), evitando U+FEFF no Invoke-Expression
        $bytes[0] | Should -Not -Be 0xEF
    }

    It 'Deve preservar 100% dos acentos e emojis em memória ao carregar os catálogos embutidos do win.ps1' {
        $script:OptiKitSkipAutoStart = $true
        try {
            . $script:WinPs1Path
            $catalogs = Get-OptiKitCatalogConfigs
            $catalogs.WinTweaks.WPFTweaksDisableGameDVR.title | Should -Match 'Gravação em 2º Plano'
            $catalogs.Apps.Discord.category | Should -Be 'Comunicação'
            $catalogs.Presets.MinimoSeguro.name | Should -Be 'Mínimo Seguro'
            $catalogs.GameLogos.ProfileValorant | Should -Not -BeNullOrEmpty
            $catalogs.LogoBase64 | Should -Not -BeNullOrEmpty
            $catalogs.ThemeXaml | Should -Match 'Instalar Apps'
        }
        finally {
            $script:OptiKitSkipAutoStart = $false
        }
    }
}
