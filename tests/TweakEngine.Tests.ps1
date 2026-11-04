# Testes do motor de Tweaks (Apply/Undo, Idempotência, <RemoveEntry>/<RemoveKey>, State Checker e Guardrails)

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'src\windows\core\logger.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\core\backup.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\hardware-utils.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\winget-engine.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\tweak-engine.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\core\state-checker.ps1')

    $script:TestRegRoot = 'HKCU:\Software\optikit-tests'
}

AfterAll {
    if (Test-Path -LiteralPath $script:TestRegRoot) {
        Remove-Item -LiteralPath $script:TestRegRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Tweak Engine & State Checker (tweak-engine.ps1 / state-checker.ps1)' {
    BeforeEach {
        if (Test-Path -LiteralPath $script:TestRegRoot) {
            Remove-Item -LiteralPath $script:TestRegRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        $testDataDir = Join-Path $TestDrive ("tweak_test_" + [Guid]::NewGuid().ToString('N'))
        Initialize-OptiKitEnvironment -DataRoot $testDataDir -DryRun:$false | Out-Null
        New-OptiKitBackupSession -SessionId '2026-11-02_16-30-00' | Out-Null
    }

    It 'Deve ser idempotente ao aplicar 3x e restaurar o valor real capturado no Undo (Híbrido)' {
        $subKey = "$script:TestRegRoot\GameDVR"
        New-Item -Path $subKey -Force | Out-Null
        # Simula que o usuário tinha valor customizado 42 antes do OptiKit (diferente do originalValue=1 do JSON)
        Set-ItemProperty -LiteralPath $subKey -Name 'GameDVR_Enabled' -Value 42 -Type DWord

        $mockTweak = [pscustomobject]@{
            title          = 'Tweak de Teste Idempotente'
            registry       = @(
                [pscustomobject]@{
                    path          = $subKey
                    name          = 'GameDVR_Enabled'
                    type          = 'DWord'
                    value         = 0
                    originalValue = 1
                }
            )
            services       = @()
            scheduledTasks = @()
            appx           = @()
            invokeScript   = @()
            undoScript     = @()
            checkScript    = $null
        }

        (Test-TweakApplied -Id 'TestIdemp' -Tweak $mockTweak) | Should -Be 'NotApplied'

        # Aplica 3 vezes seguidas
        Invoke-Tweak -Id 'TestIdemp' -Tweak $mockTweak -Mode 'Apply' | Out-Null
        Invoke-Tweak -Id 'TestIdemp' -Tweak $mockTweak -Mode 'Apply' | Out-Null
        Invoke-Tweak -Id 'TestIdemp' -Tweak $mockTweak -Mode 'Apply' | Out-Null

        (Get-ItemProperty -LiteralPath $subKey -Name 'GameDVR_Enabled').GameDVR_Enabled | Should -Be 0
        (Test-TweakApplied -Id 'TestIdemp' -Tweak $mockTweak) | Should -Be 'Applied'

        # O Undo deve restaurar 42 (o valor real capturado antes da 1ª execução), não 1
        Invoke-Tweak -Id 'TestIdemp' -Tweak $mockTweak -Mode 'Undo' | Out-Null
        (Get-ItemProperty -LiteralPath $subKey -Name 'GameDVR_Enabled').GameDVR_Enabled | Should -Be 42
        (Test-TweakApplied -Id 'TestIdemp' -Tweak $mockTweak) | Should -Be 'NotApplied'
    }

    It 'Deve cair no originalValue do JSON quando não houver captura prévia no state.json' {
        $subKey = "$script:TestRegRoot\Fallback"
        New-Item -Path $subKey -Force | Out-Null
        Set-ItemProperty -LiteralPath $subKey -Name 'TestVal' -Value 0 -Type DWord

        $mockTweak = [pscustomobject]@{
            title          = 'Tweak Fallback'
            registry       = @(
                [pscustomobject]@{
                    path          = $subKey
                    name          = 'TestVal'
                    type          = 'DWord'
                    value         = 0
                    originalValue = 7
                }
            )
            services       = @()
            scheduledTasks = @()
            appx           = @()
            invokeScript   = @()
            undoScript     = @()
            checkScript    = $null
        }

        Invoke-Tweak -Id 'TestFallback' -Tweak $mockTweak -Mode 'Undo' | Out-Null
        (Get-ItemProperty -LiteralPath $subKey -Name 'TestVal').TestVal | Should -Be 7
    }

    It 'Deve suportar <RemoveEntry> e <RemoveKey> (incluindo valor Default de CLSID)' {
        $entryKey = "$script:TestRegRoot\Policies"
        $clsidKey = "$script:TestRegRoot\CLSID\InprocServer32"

        $mockTweak = [pscustomobject]@{
            title          = 'Tweak RemoveEntry e RemoveKey'
            registry       = @(
                [pscustomobject]@{
                    path          = $entryKey
                    name          = 'AllowTelemetry'
                    type          = 'DWord'
                    value         = 0
                    originalValue = '<RemoveEntry>'
                },
                [pscustomobject]@{
                    path          = $clsidKey
                    name          = '(Default)'
                    type          = 'String'
                    value         = ''
                    originalValue = '<RemoveKey>'
                }
            )
            services       = @()
            scheduledTasks = @()
            appx           = @()
            invokeScript   = @()
            undoScript     = @()
            checkScript    = $null
        }

        Invoke-Tweak -Id 'TestSentinels' -Tweak $mockTweak -Mode 'Apply' | Out-Null
        (Test-Path -LiteralPath $clsidKey) | Should -BeTrue
        (Test-TweakApplied -Id 'TestSentinels' -Tweak $mockTweak) | Should -Be 'Applied'

        Invoke-Tweak -Id 'TestSentinels' -Tweak $mockTweak -Mode 'Undo' | Out-Null
        (Test-Path -LiteralPath $clsidKey) | Should -BeFalse
        $entryState = Get-RegistryEntryState -Path $entryKey -Name 'AllowTelemetry'
        $entryState.ValueExisted | Should -BeFalse
    }

    It 'Deve bloquear em runtime qualquer tentativa de tocar em vgc/vgk ou EnableVirtualizationBasedSecurity' {
        $badServiceTweak = [pscustomobject]@{
            title          = 'Tweak Malicioso Vanguard'
            registry       = @()
            services       = @(
                [pscustomobject]@{ name = 'vgc'; startupType = 'Disabled'; originalType = 'Demand' }
            )
            scheduledTasks = @()
            appx           = @()
            invokeScript   = @()
            undoScript     = @()
        }

        { Invoke-Tweak -Id 'BadVgc' -Tweak $badServiceTweak -Mode 'Apply' } | Should -Throw '*GUARDRAIL ANTI-CHEAT*'

        $badVbsTweak = [pscustomobject]@{
            title          = 'Tweak Malicioso VBS'
            registry       = @(
                [pscustomobject]@{
                    path          = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
                    name          = 'EnableVirtualizationBasedSecurity'
                    type          = 'DWord'
                    value         = 0
                    originalValue = 1
                }
            )
            services       = @()
            scheduledTasks = @()
            appx           = @()
            invokeScript   = @()
            undoScript     = @()
        }

        { Invoke-Tweak -Id 'BadVbs' -Tweak $badVbsTweak -Mode 'Apply' } | Should -Throw '*GUARDRAIL ANTI-CHEAT*'
    }
}
