# Testes de schema, integridade referencial, guardrails anti-cheat e filosofia anti-placebo dos JSONs

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:AppsPath = Join-Path $script:RepoRoot 'config\apps.json'
    $script:TweaksPath = Join-Path $script:RepoRoot 'config\win-tweaks.json'
    $script:GamesPath = Join-Path $script:RepoRoot 'config\game-profiles.json'
    $script:PresetsPath = Join-Path $script:RepoRoot 'config\presets.json'

    $script:Apps = [System.IO.File]::ReadAllText($script:AppsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $script:Tweaks = [System.IO.File]::ReadAllText($script:TweaksPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $script:Games = [System.IO.File]::ReadAllText($script:GamesPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $script:Presets = [System.IO.File]::ReadAllText($script:PresetsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
}

Describe 'Validação de Schema e Integridade dos Catálogos JSON' {
    Context 'config/apps.json' {
        It 'Deve conter pelo menos 30 aplicativos mapeados nas 5 categorias da especificação' {
            $props = @($script:Apps.PSObject.Properties)
            $props.Count | Should -BeGreaterOrEqual 30

            $validCategories = @(
                'Navegadores',
                'Comunicação',
                'Jogos & Launchers',
                'Runtimes & Utilitários',
                'Desenvolvimento'
            )

            foreach ($p in $props) {
                $app = $p.Value
                $app.name | Should -Not -BeNullOrEmpty
                $app.description | Should -Not -BeNullOrEmpty
                $app.winget | Should -Not -BeNullOrEmpty
                $validCategories | Should -Contain $app.category
            }
        }
    }

    Context 'config/win-tweaks.json' {
        It 'Deve conter pelo menos 25 tweaks com todos os campos obrigatórios de impacto, risco e rationale' {
            $props = @($script:Tweaks.PSObject.Properties)
            $props.Count | Should -BeGreaterOrEqual 25

            $validImpacts = @('Alto', 'Médio', 'Baixo', 'Situacional')
            $validRisks = @('Safe', 'Moderate', 'Advanced')

            foreach ($p in $props) {
                $t = $p.Value
                $t.title | Should -Not -BeNullOrEmpty
                $t.category | Should -Not -BeNullOrEmpty
                $t.description | Should -Not -BeNullOrEmpty
                $t.rationale | Should -Not -BeNullOrEmpty
                $validImpacts | Should -Contain $t.impact
                $validRisks | Should -Contain $t.riskLevel
                @($t.osSupport).Count | Should -BeGreaterOrEqual 1
            }
        }

        It 'Todo tweak deve possuir verificador de estado (implícito ou checkScript explícito) e mecanismo de reversão' {
            foreach ($p in $script:Tweaks.PSObject.Properties) {
                $t = $p.Value
                $hasImplicit = (@($t.registry).Count -gt 0) -or (@($t.services).Count -gt 0) -or (@($t.scheduledTasks).Count -gt 0) -or (@($t.appx).Count -gt 0)
                $hasCheck = -not [string]::IsNullOrWhiteSpace($t.checkScript)
                ($hasImplicit -or $hasCheck) | Should -BeTrue -Because "Tweak '$($p.Name)' precisa de verificador de estado"

                foreach ($reg in @($t.registry)) {
                    $reg.path | Should -Not -BeNullOrEmpty
                    $reg.name | Should -Not -BeNullOrEmpty
                    $null -ne $reg.originalValue | Should -BeTrue -Because "Registro em '$($p.Name)' precisa de originalValue"
                }

                foreach ($apx in @($t.appx)) {
                    $apx.name | Should -Not -BeNullOrEmpty
                    $apx.storeId | Should -Not -BeNullOrEmpty -Because "Appx '$($apx.name)' em '$($p.Name)' exige storeId para Undo via winget"
                }
            }
        }

        It 'Não deve remover pacotes essenciais protegidos (Store, Calculadora, Captura de Tela, Xbox Identity Provider)' {
            $protectedAppx = @(
                'Microsoft.WindowsStore',
                'Microsoft.WindowsCalculator',
                'Microsoft.ScreenSketch',
                'Microsoft.XboxIdentityProvider',
                'Microsoft.GamingServices',
                'Microsoft.DesktopAppInstaller'
            )

            foreach ($p in $script:Tweaks.PSObject.Properties) {
                foreach ($apx in @($p.Value.appx)) {
                    $protectedAppx | Should -Not -Contain $apx.name
                }
            }
        }

        It 'Guardrail Anti-Cheat: não deve tocar em vgc, vgk, TPM, SecureBoot ou desativar VBS globalmente' {
            $rawJson = [System.IO.File]::ReadAllText($script:TweaksPath, [System.Text.Encoding]::UTF8)
            $rawJson | Should -Not -Match '(?i)"name"\s*:\s*"(vgc|vgk)"'
            $rawJson | Should -Not -Match '(?i)EnableVirtualizationBasedSecurity'

            $hvci = $script:Tweaks.WPFTweaksDisableHVCI
            $null -ne $hvci | Should -BeTrue
            $hvci.riskLevel | Should -Be 'Advanced'
            $hvci.requiresReboot | Should -BeTrue
            $hvci.confirmMessage | Should -Match 'Vanguard'
        }
    }

    Context 'config/game-profiles.json' {
        It 'Deve conter VALORANT, CS2 e UE5 ativos com otimizações e as ferramentas globais' {
            $val = $script:Games.ProfileValorant
            $null -ne $val | Should -BeTrue
            $val.status | Should -Be 'active'
            @($val.optimizations).Count | Should -Be 4

            $script:Games.ProfileCS2.status | Should -Be 'active'
            @($script:Games.ProfileCS2.optimizations).Count | Should -Be 3

            $script:Games.ProfileUE5.status | Should -Be 'active'
            @($script:Games.ProfileUE5.optimizations).Count | Should -Be 3

            $script:Games.GlobalGamingTools.status | Should -Be 'global'
        }
    }

    Context 'config/presets.json' {
        It 'Deve referenciar apenas IDs existentes e manter itens Advanced/Baixo/Situacional desmarcados' {
            $tweakMap = @{}
            foreach ($p in $script:Tweaks.PSObject.Properties) { $tweakMap[$p.Name] = $p.Value }

            $appMap = @{}
            foreach ($p in $script:Apps.PSObject.Properties) { $appMap[$p.Name] = $p.Value }

            $gameOptMap = @{}
            foreach ($gp in $script:Games.PSObject.Properties) {
                foreach ($opt in @($gp.Value.optimizations)) {
                    $gameOptMap[$opt.id] = $opt
                }
            }

            foreach ($presetProp in $script:Presets.PSObject.Properties) {
                $preset = $presetProp.Value
                foreach ($tid in @($preset.tweaks)) {
                    $tweakMap.ContainsKey($tid) | Should -BeTrue -Because "Preset '$($presetProp.Name)' referencia tweak '$tid'"
                    $tweak = $tweakMap[$tid]
                    $tweak.riskLevel | Should -Not -Be 'Advanced'
                    $tweak.impact | Should -Not -BeIn @('Baixo', 'Situacional')
                }
                foreach ($aid in @($preset.apps)) {
                    $appMap.ContainsKey($aid) | Should -BeTrue -Because "Preset '$($presetProp.Name)' referencia app '$aid'"
                }
                foreach ($gid in @($preset.gameOptimizations)) {
                    $gameOptMap.ContainsKey($gid) | Should -BeTrue -Because "Preset '$($presetProp.Name)' referencia game opt '$gid'"
                    $gopt = $gameOptMap[$gid]
                    $gopt.impact | Should -Not -BeIn @('Baixo', 'Situacional')
                }
            }
        }
    }
}
