# Verifica que toda função referenciada nos catálogos existe e está na whitelist correta

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'src\windows\core\logger.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\core\backup.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\hardware-utils.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\winget-engine.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\tweak-engine.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\game-engine.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\maintenance.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\core\state-checker.ps1')

    $script:Tweaks = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'config\win-tweaks.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $script:Games = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'config\game-profiles.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
}

Describe 'Whitelists de helpers' {
    It 'Todo invokeScript/undoScript existe e está na whitelist de tweaks' {
        foreach ($p in $script:Tweaks.PSObject.Properties) {
            foreach ($fn in (@($p.Value.invokeScript) + @($p.Value.undoScript))) {
                if ([string]::IsNullOrWhiteSpace($fn)) { continue }
                (Get-Command -Name $fn -CommandType Function -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty -Because "$($p.Name) referencia $fn"
                $script:AllowedTweakScripts | Should -Contain $fn -Because "$($p.Name) referencia $fn"
            }
        }
    }

    It 'Todo checkScript existe e está na whitelist de checks' {
        foreach ($p in $script:Tweaks.PSObject.Properties) {
            $fn = $p.Value.checkScript
            if ([string]::IsNullOrWhiteSpace($fn)) { continue }
            (Get-Command -Name $fn -CommandType Function -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty -Because "$($p.Name) referencia $fn"
            $script:AllowedCheckScripts | Should -Contain $fn -Because "$($p.Name) referencia $fn"
        }
    }

    It 'Toda action de game profile existe e está na whitelist de jogos' {
        foreach ($g in $script:Games.PSObject.Properties) {
            foreach ($opt in @($g.Value.optimizations)) {
                $fn = $opt.action
                if ([string]::IsNullOrWhiteSpace($fn)) { continue }
                (Get-Command -Name $fn -CommandType Function -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty -Because "$($g.Name)/$($opt.id) referencia $fn"
                $script:AllowedGameActions | Should -Contain $fn -Because "$($g.Name)/$($opt.id) referencia $fn"
            }
        }
    }
}
