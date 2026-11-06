# Testes de automação v0.2: perfis, plano de undo, relatório e modo desatendido

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

    $script:OptiKitVersion = '0.3.0'
    $script:Configs = @{
        Apps         = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'config\apps.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        WinTweaks    = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'config\win-tweaks.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        GameProfiles = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'config\game-profiles.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        Presets      = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'config\presets.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    }
}

Describe 'Automação v0.2' {
    It 'Deve exportar e reimportar um perfil com IDs válidos' {
        $profile = ConvertTo-OptiKitProfile -Tweaks @('WPFTweaksDisableGameDVR', 'WPFTweaksEdgeTelemetry') -GameOptimizations @('Global_OptimizeUSB') -Apps @('VCRedistX64') -Preset 'GamerRecomendado'
        $profile.schemaVersion | Should -Be 1
        @($profile.tweaks).Count | Should -Be 2

        $path = Join-Path $TestDrive 'profile.json'
        [System.IO.File]::WriteAllText($path, ($profile | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))

        $selection = ConvertFrom-OptiKitProfile -Path $path -Configs $script:Configs
        @($selection.Tweaks).Count | Should -Be 2
        @($selection.GameOptimizations) | Should -Contain 'Global_OptimizeUSB'
        @($selection.Apps) | Should -Contain 'VCRedistX64'
    }

    It 'Deve rejeitar perfil com ID inexistente e uso simultâneo de -Preset/-Config' {
        $badProfile = [pscustomobject]@{
            schemaVersion     = 1
            tweaks            = @('WPFTweaksNaoExiste')
            gameOptimizations = @()
            apps              = @()
        }
        $badPath = Join-Path $TestDrive 'bad-profile.json'
        [System.IO.File]::WriteAllText($badPath, ($badProfile | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))

        { ConvertFrom-OptiKitProfile -Path $badPath -Configs $script:Configs } | Should -Throw '*não existe*'
        { Resolve-OptiKitSelection -Configs $script:Configs -PresetKey 'MinimoSeguro' -ConfigPath $badPath } | Should -Throw '*apenas*'
    }

    It 'Deve classificar tweaks, game opts e estados auxiliares no plano de Reverter Tudo' {
        $state = @{
            'WPFTweaksDisableGameDVR' = [pscustomobject]@{ appliedAt = '2026-11-04T10:00:00'; session = 's1'; captured = @() }
            'Global_OptimizeUSB'      = [pscustomobject]@{ appliedAt = '2026-11-04T10:01:00'; session = 's1'; captured = @() }
            'PowerPlanOriginal'       = [pscustomobject]@{ appliedAt = '2026-11-04T10:02:00'; session = 's1'; captured = @() }
            'DirectXGlobalSettings'   = [pscustomobject]@{ appliedAt = '2026-11-04T10:03:00'; session = 's1'; captured = @() }
        }

        $plan = Get-OptiKitStateUndoPlan -StateData $state -Configs $script:Configs
        @($plan).Count | Should -Be 4
        $plan[0].Key | Should -Be 'DirectXGlobalSettings'
        ($plan | Where-Object { $_.Key -eq 'WPFTweaksDisableGameDVR' }).Kind | Should -Be 'Tweak'
        ($plan | Where-Object { $_.Key -eq 'Global_OptimizeUSB' }).Kind | Should -Be 'GameOpt'
        ($plan | Where-Object { $_.Key -eq 'PowerPlanOriginal' }).Kind | Should -Be 'PowerPlan'
    }

    It 'Deve reverter um tweak de teste via Reverter Tudo' {
        $testRoot = Join-Path $TestDrive ("revert_test_" + [Guid]::NewGuid().ToString('N'))
        Initialize-OptiKitEnvironment -DataRoot $testRoot -DryRun:$false | Out-Null
        New-OptiKitBackupSession -SessionId '2026-11-04_11-00-00' | Out-Null

        $regKey = 'HKCU:\Software\optikit-tests-revert'
        if (Test-Path -LiteralPath $regKey) {
            Remove-Item -LiteralPath $regKey -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -Path $regKey -Force | Out-Null
        Set-ItemProperty -LiteralPath $regKey -Name 'Value' -Value 42 -Type DWord

        $mockTweak = [pscustomobject]@{
            title          = 'Tweak de Reversão'
            registry       = @(
                [pscustomobject]@{ path = $regKey; name = 'Value'; type = 'DWord'; value = 0; originalValue = 1 }
            )
            services       = @()
            scheduledTasks = @()
            appx           = @()
            invokeScript   = @()
            undoScript     = @()
            checkScript    = $null
        }

        $configs = $script:Configs.Clone()
        $configs.WinTweaks = $script:Configs.WinTweaks | Select-Object
        $configs.WinTweaks | Add-Member -NotePropertyName 'TestRevertTweak' -NotePropertyValue $mockTweak

        Invoke-Tweak -Id 'TestRevertTweak' -Tweak $mockTweak -Mode 'Apply' | Out-Null
        (Get-ItemProperty -LiteralPath $regKey -Name 'Value').Value | Should -Be 0

        $result = Invoke-OptiKitRevertAll -Configs $configs
        $result | Should -Be 0
        (Get-ItemProperty -LiteralPath $regKey -Name 'Value').Value | Should -Be 42

        Remove-Item -LiteralPath $regKey -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Deve gerar relatório HTML com hardware, estado, diagnóstico, contagens e log' {
        $testRoot = Join-Path $TestDrive ("report_test_" + [Guid]::NewGuid().ToString('N'))
        Initialize-OptiKitEnvironment -DataRoot $testRoot -DryRun:$false | Out-Null
        Write-OptimizerLog -Level INFO -Message 'linha de teste do relatório'
        Save-CapturedState -Id 'ReportTweak' -CapturedItems @(
            @{ kind = 'registry'; path = 'HKCU:\Software\Teste'; name = 'Value'; existed = $true; value = 42 }
        )

        $diagnostics = @(
            [pscustomobject]@{
                Status     = 'Warn'
                Title      = 'Teste Diagnóstico'
                Summary    = 'Resumo do teste'
                Detail     = 'Detalhe do teste'
                ActionText = 'Ação do teste'
            }
        )
        $counts = @{ Applied = 3; Skipped = 2; Failed = 1 }

        $reportPath = Export-OptiKitReport -OutputDirectory (Join-Path $testRoot 'reports') -Diagnostics $diagnostics -Counts $counts
        Test-Path -LiteralPath $reportPath | Should -BeTrue
        $content = [System.IO.File]::ReadAllText($reportPath, [System.Text.Encoding]::UTF8)
        $content | Should -Match 'OptiKit v0\.3\.0'
        $content | Should -Match 'linha de teste do relatório'
        $content | Should -Match 'Resumo da sessão'
        $content | Should -Match 'Operações OK'
        $content | Should -Match 'Teste Diagnóstico'
        $content | Should -Match 'Ação do teste'
        $content | Should -Match 'Valores capturados'
        $content | Should -Match 'ReportTweak'
        $content | Should -Match '"value":42'
    }

    It 'Deve avisar ao importar perfil criado por uma versão mais nova' {
        $profile = [pscustomobject]@{
            schemaVersion     = 1
            optikitVersion    = '9.9.9'
            preset            = 'Futuro'
            tweaks            = @('WPFTweaksDisableGameDVR')
            gameOptimizations = @()
            apps              = @()
        }
        $path = Join-Path $TestDrive 'perfil_versao_futura.json'
        [System.IO.File]::WriteAllText($path, ($profile | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))

        $script:OptiKit.LogHistory.Clear()
        $selection = ConvertFrom-OptiKitProfile -Path $path -Configs $script:Configs
        @($selection.Tweaks).Count | Should -Be 1
        ($script:OptiKit.LogHistory -join "`n") | Should -Match 'v9\.9\.9'
    }

    It 'Deve executar o modo desatendido em dry-run sem GUI e sair com código 0' {
        $winPs1 = Join-Path $script:RepoRoot 'win.ps1'
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
        $psi.Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -DryRun -Silent -Preset MinimoSeguro -NoElevate' -f $winPs1)
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        try {
            $exited = $proc.WaitForExit(60000)
            $exited | Should -BeTrue
            $proc.ExitCode | Should -Be 0
        }
        finally {
            if ($proc -and (-not $proc.HasExited)) {
                try { $proc.Kill() } catch { Write-Verbose $_.Exception.Message }
            }
        }
    }

    It 'Deve sair com código 2 no modo desatendido quando o perfil contém tweak inexistente' {
        $winPs1 = Join-Path $script:RepoRoot 'win.ps1'
        $profilePath = Join-Path $TestDrive 'perfil_tweak_inexistente.json'
        $profileJson = '{ "schemaVersion": 1, "preset": "MinimoSeguro", "tweaks": [ "NaoExiste" ], "gameOptimizations": [], "apps": [] }'
        [System.IO.File]::WriteAllText($profilePath, $profileJson, (New-Object System.Text.ASCIIEncoding))

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
        $psi.Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -DryRun -Silent -Config "{1}" -NoElevate' -f $winPs1, $profilePath)
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        try {
            $exited = $proc.WaitForExit(60000)
            $exited | Should -BeTrue
            $stdout = $proc.StandardOutput.ReadToEnd()
            $proc.ExitCode | Should -Be 2
            $stdout | Should -Match "Tweak 'NaoExiste'"
        }
        finally {
            if ($proc -and (-not $proc.HasExited)) {
                try { $proc.Kill() } catch { Write-Verbose $_.Exception.Message }
            }
        }
    }

    It 'Deve filtrar HAGS de preset em GPU de 8 GB, manter em 16 GB e preservar perfil importado' {
        $presets = $script:Configs.Presets | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $presets | Add-Member -NotePropertyName 'HagsTest' -NotePropertyValue ([pscustomobject]@{
            name              = 'HAGS Test'
            description       = 'Preset sintético'
            tweaks            = @('WPFTweaksEnableHAGS')
            gameOptimizations = @()
            apps              = @()
        })
        $configs = @{
            Apps         = $script:Configs.Apps
            WinTweaks    = $script:Configs.WinTweaks
            GameProfiles = $script:Configs.GameProfiles
            Presets      = $presets
        }

        Mock Get-OptiKitHardware { [pscustomobject]@{ GpuVramGB = 8 } }
        $selection = Resolve-OptiKitSelection -Configs $configs -PresetKey 'HagsTest'
        @($selection.Tweaks) | Should -Not -Contain 'WPFTweaksEnableHAGS'

        Mock Get-OptiKitHardware { [pscustomobject]@{ GpuVramGB = 16 } }
        $selection16 = Resolve-OptiKitSelection -Configs $configs -PresetKey 'HagsTest'
        @($selection16.Tweaks) | Should -Contain 'WPFTweaksEnableHAGS'

        $profile = ConvertTo-OptiKitProfile -Tweaks @('WPFTweaksEnableHAGS') -GameOptimizations @() -Apps @() -Preset 'GamerRecomendado'
        $profilePath = Join-Path $TestDrive 'perfil_hags.json'
        [System.IO.File]::WriteAllText($profilePath, ($profile | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
        Mock Get-OptiKitHardware { [pscustomobject]@{ GpuVramGB = 8 } }
        $fromProfile = Resolve-OptiKitSelection -Configs $script:Configs -ConfigPath $profilePath
        @($fromProfile.Tweaks) | Should -Contain 'WPFTweaksEnableHAGS'
    }
}
