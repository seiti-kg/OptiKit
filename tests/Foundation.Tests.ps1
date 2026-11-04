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

    It 'Deve classificar flags X3D e dual-CCD via Resolve-OptiKitCpuFlags' {
        $matrix = @(
            @{ Name = 'AMD Ryzen 7 7800X3D 8-Core Processor'; Cores = 8; IsX3D = $true; IsDual = $false }
            @{ Name = 'AMD Ryzen 9 7950X3D 16-Core Processor'; Cores = 16; IsX3D = $true; IsDual = $true }
            @{ Name = 'AMD Ryzen 9 9900X3D 12-Core Processor'; Cores = 12; IsX3D = $true; IsDual = $true }
            @{ Name = 'AMD Ryzen 9 7945HX3D with Radeon Graphics'; Cores = 16; IsX3D = $true; IsDual = $true }
            @{ Name = 'AMD Ryzen 9 9955HX3D with Radeon Graphics'; Cores = 16; IsX3D = $true; IsDual = $true }
            @{ Name = 'AMD Ryzen 7 9700X 8-Core Processor'; Cores = 8; IsX3D = $false; IsDual = $false }
            @{ Name = 'AMD Ryzen 9 7950X 16-Core Processor'; Cores = 16; IsX3D = $false; IsDual = $false }
        )

        foreach ($case in $matrix) {
            $flags = Resolve-OptiKitCpuFlags -CpuName $case.Name -CpuCores $case.Cores
            $flags.IsX3D | Should -Be $case.IsX3D -Because ("IsX3D de '{0}' deve ser {1}" -f $case.Name, $case.IsX3D)
            $flags.IsX3DDualCcd | Should -Be $case.IsDual -Because ("IsX3DDualCcd de '{0}' deve ser {1}" -f $case.Name, $case.IsDual)
        }
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

    It 'Deve classificar suporte de OS e build via Test-OptiKitTweakSupported' {
        $win10 = [pscustomobject]@{ IsWin11 = $false; OsBuild = 19045 }
        $win11 = [pscustomobject]@{ IsWin11 = $true; OsBuild = 26100 }
        $win11Old = [pscustomobject]@{ IsWin11 = $true; OsBuild = 22000 }

        $win11Only = [pscustomobject]@{ osSupport = @('Win11'); minBuild = 22621 }
        $both = [pscustomobject]@{ osSupport = @('Win10', 'Win11'); minBuild = $null }
        $legacy = [pscustomobject]@{ osSupport = @(); minBuild = $null }

        (Test-OptiKitTweakSupported -Tweak $win11Only -Hardware $win10) | Should -BeFalse
        (Test-OptiKitTweakSupported -Tweak $win11Only -Hardware $win11Old) | Should -BeFalse
        (Test-OptiKitTweakSupported -Tweak $win11Only -Hardware $win11) | Should -BeTrue
        (Test-OptiKitTweakSupported -Tweak $both -Hardware $win10) | Should -BeTrue
        (Test-OptiKitTweakSupported -Tweak $legacy -Hardware $win10) | Should -BeTrue
    }

    It 'Deve ignorar Apply de tweak exclusivo de Win11 em Windows 10 sem gravar no registro' {
        $subKey = "$script:TestRegRoot\Win11Only"
        $mockTweak = [pscustomobject]@{
            title          = 'Exclusivo Win11'
            osSupport      = @('Win11')
            minBuild       = 22621
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
            CpuName         = 'Fake Win10'
            CpuCores        = 4
            IsX3D           = $false
            IsX3DDualCcd    = $false
            IsLaptop        = $false
            GpuNames        = @()
            GpuVendors      = @()
            SystemDiskIsSSD = $true
            OsBuild         = 19045
            IsWin11         = $false
            Summary         = 'fake'
        }

        $result = Invoke-Tweak -Id 'Win11OnlyTest' -Tweak $mockTweak -Mode 'Apply'
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
