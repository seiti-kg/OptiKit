# Testes da fundação v0.2: bloqueio por hardware e merge do DirectXUserGlobalSettings

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

    $script:TestRegRoot = 'HKCU:\Software\optikit-tests-v02'
}

AfterAll {
    if (Test-Path -LiteralPath $script:TestRegRoot) {
        Remove-Item -LiteralPath $script:TestRegRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Fundação v0.2 (hardware guard + DirectX)' {
    BeforeEach {
        if (Test-Path -LiteralPath $script:TestRegRoot) {
            Remove-Item -LiteralPath $script:TestRegRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        $testDataDir = Join-Path $TestDrive ("foundation_test_" + [Guid]::NewGuid().ToString('N'))
        Initialize-OptiKitEnvironment -DataRoot $testDataDir -DryRun:$false | Out-Null
        New-OptiKitBackupSession -SessionId '2026-11-04_10-00-00' | Out-Null
        $script:OptiKitHardwareCache = $null
    }

    It 'Deve bloquear tweaks X3D dual-CCD e liberar em hardware single-CCD' {
        $tweak = [pscustomobject]@{
            blockedOn      = @('X3DDualCcd')
            blockedMessage = 'Motivo de teste'
        }
        $dual = [pscustomobject]@{ IsX3D = $true; IsX3DDualCcd = $true; IsLaptop = $false }
        $single = [pscustomobject]@{ IsX3D = $true; IsX3DDualCcd = $false; IsLaptop = $false }

        (Test-OptiKitTweakBlocked -Tweak $tweak -Hardware $dual) | Should -Be 'Motivo de teste'
        (Test-OptiKitTweakBlocked -Tweak $tweak -Hardware $single) | Should -BeNullOrEmpty
    }

    It 'Deve ignorar Apply de tweak bloqueado sem gravar no registro' {
        $subKey = "$script:TestRegRoot\Blocked"
        $mockTweak = [pscustomobject]@{
            title          = 'Bloqueado'
            blockedOn      = @('X3DDualCcd')
            blockedMessage = 'Bloqueado no teste'
            registry       = @(
                [pscustomobject]@{ path = $subKey; name = 'Value'; type = 'DWord'; value = 1; originalValue = 0 }
            )
            services       = @()
            scheduledTasks = @()
            appx           = @()
            invokeScript   = @()
            undoScript     = @()
            checkScript    = $null
        }

        $script:OptiKitHardwareCache = [pscustomobject]@{
            CpuName         = 'AMD Ryzen 9 9950X3D'
            CpuCores        = 16
            IsX3D           = $true
            IsX3DDualCcd    = $true
            IsLaptop        = $false
            GpuNames        = @()
            GpuVendors      = @()
            SystemDiskIsSSD = $true
            OsBuild         = 26100
            IsWin11         = $true
            Summary         = 'fake'
        }

        $result = Invoke-Tweak -Id 'BlockedTest' -Tweak $mockTweak -Mode 'Apply'
        $result | Should -BeFalse
        (Test-Path -LiteralPath $subKey) | Should -BeFalse
    }

    It 'Deve fazer merge e restaurar a string DirectXUserGlobalSettings preservando AutoHDR e VRR' {
        $key = "$script:TestRegRoot\DirectX"
        New-Item -Path $key -Force | Out-Null
        $original = 'AutoHDREnable=1;VRROptimizeEnable=1;'
        Set-ItemProperty -LiteralPath $key -Name 'DirectXUserGlobalSettings' -Value $original -Type String

        Enable-OptiKitWindowedGameOptimizations -RegistryPath $key
        $after = (Get-ItemProperty -LiteralPath $key -Name 'DirectXUserGlobalSettings').DirectXUserGlobalSettings
        $after | Should -Match 'AutoHDREnable=1'
        $after | Should -Match 'VRROptimizeEnable=1'
        $after | Should -Match 'SwapEffectUpgradeEnable=1'
        (Test-OptiKitWindowedGameOptimizations -RegistryPath $key) | Should -BeTrue

        Disable-OptiKitWindowedGameOptimizations
        $restored = (Get-ItemProperty -LiteralPath $key -Name 'DirectXUserGlobalSettings').DirectXUserGlobalSettings
        $restored | Should -Be $original
    }
}
