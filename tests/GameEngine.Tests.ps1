# Testes unitários do motor de Jogos (detecção de executável, whitelist de actions, FSO/GPU flags e Shader Cache)

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'src\windows\core\logger.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\core\backup.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\hardware-utils.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\winget-engine.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\tweak-engine.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\game-engine.ps1')
}

Describe 'Game Engine (game-engine.ps1)' {
    BeforeEach {
        $testRoot = Join-Path $TestDrive ("game_test_" + [Guid]::NewGuid().ToString('N'))
        Initialize-OptiKitEnvironment -DataRoot $testRoot -DryRun:$false | Out-Null
        New-OptiKitBackupSession -SessionId '2026-11-02_16-35-00' | Out-Null
    }

    It 'Deve detectar o executável do jogo via defaultPaths e via RiotClientInstalls.json' {
        $fakeRiotDir = Join-Path $TestDrive 'Riot Games\VALORANT\live'
        $fakeBinDir = Join-Path $fakeRiotDir 'ShooterGame\Binaries\Win64'
        New-Item -Path $fakeBinDir -ItemType Directory -Force | Out-Null
        $fakeExe = Join-Path $fakeBinDir 'VALORANT-Win64-Shipping.exe'
        Set-Content -LiteralPath $fakeExe -Value 'dummy-binary'

        $profileDirect = [pscustomobject]@{
            gameName            = 'VALORANT'
            executableDetection = [pscustomobject]@{
                defaultPaths     = @($fakeExe)
                registryFallback = $null
            }
        }
        (Find-GameExecutable -ProfileConfig $profileDirect) | Should -Be $fakeExe

        $riotInstallsFile = Join-Path $TestDrive 'RiotClientInstalls.json'
        $riotJsonObj = @{
            associated_client = @{
                ($fakeRiotDir -replace '\\', '/') = 'C:/Riot Games/Riot Client/RiotClientServices.exe'
            }
        }
        $riotJsonObj | ConvertTo-Json | Set-Content -LiteralPath $riotInstallsFile -Encoding UTF8

        $profileViaJson = [pscustomobject]@{
            gameName            = 'VALORANT'
            executableDetection = [pscustomobject]@{
                defaultPaths       = @('C:\Caminho\Inexistente\VALORANT.exe')
                registryFallback   = $null
                riotClientFallback = $true
            }
        }
        (Find-GameExecutable -ProfileConfig $profileViaJson -RiotInstallsPath $riotInstallsFile) | Should -Be $fakeExe
    }

    It 'Não deve usar o RiotClientInstalls.json para perfis que não são do Riot Client' {
        $fakeRiotDir = Join-Path $TestDrive 'Riot Games\VALORANT\live'
        $fakeBinDir = Join-Path $fakeRiotDir 'ShooterGame\Binaries\Win64'
        New-Item -Path $fakeBinDir -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $fakeBinDir 'VALORANT-Win64-Shipping.exe') -Value 'dummy-binary'
        $riotInstallsFile = Join-Path $TestDrive 'RiotClientInstalls.json'
        @{ associated_client = @{ ($fakeRiotDir -replace '\\', '/') = 'C:/Riot Games/Riot Client/RiotClientServices.exe' } } |
            ConvertTo-Json | Set-Content -LiteralPath $riotInstallsFile -Encoding UTF8

        $cs2Profile = [pscustomobject]@{
            gameName            = 'Counter-Strike 2'
            executableDetection = [pscustomobject]@{
                defaultPaths     = @('C:\Caminho\Inexistente\cs2.exe')
                registryFallback = $null
            }
        }
        (Find-GameExecutable -ProfileConfig $cs2Profile -RiotInstallsPath $riotInstallsFile) | Should -BeNullOrEmpty
    }

    It 'Deve rejeitar qualquer action que não esteja na whitelist de segurança' {
        $dummyProfile = [pscustomobject]@{ gameName = 'TestGame' }
        $badOpt = [pscustomobject]@{
            id     = 'Bad_Opt'
            title  = 'Executar Comando Arbitrário'
            action = 'Invoke-ArbitraryCommand'
        }

        { Invoke-GameOptimization -ProfileConfig $dummyProfile -Optimization $badOpt -Mode 'Apply' } | Should -Throw '*whitelist*'
    }

    It 'Deve retornar falso quando o executável do jogo não é encontrado' {
        $profile = [pscustomobject]@{
            gameName            = 'Jogo Ausente'
            executableDetection = [pscustomobject]@{
                defaultPaths     = @('C:\Caminho\Inexistente\Jogo.exe')
                registryFallback = $null
            }
        }
        $opt = [pscustomobject]@{
            id     = 'Missing_Opt'
            title  = 'Otimização de jogo ausente'
            action = 'Set-AppCompatFlags'
            flags  = '~ HIGHDPIAWARE'
        }

        Mock Find-GameExecutable { $null }
        (Invoke-GameOptimization -ProfileConfig $profile -Optimization $opt -Mode 'Apply') | Should -BeFalse
    }

    It 'Deve limpar diretórios de Cache de Shaders com segurança e contabilizar arquivos removidos' {
        $fakeCache1 = Join-Path $TestDrive 'FakeShaderCache\DXCache'
        $fakeCache2 = Join-Path $TestDrive 'FakeShaderCache\D3DSCache'
        New-Item -Path $fakeCache1 -ItemType Directory -Force | Out-Null
        New-Item -Path $fakeCache2 -ItemType Directory -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $fakeCache1 'shader1.bin') -Value ('A' * 1024)
        Set-Content -LiteralPath (Join-Path $fakeCache2 'shader2.bin') -Value ('B' * 2048)

        Clear-ShaderCache -TargetDirectories @($fakeCache1, $fakeCache2)

        @(Get-ChildItem -LiteralPath $fakeCache1 -File).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $fakeCache2 -File).Count | Should -Be 0
        ($script:OptiKit.LogHistory -join "`n") | Should -Match '2 arquivos removidos'
    }
}
