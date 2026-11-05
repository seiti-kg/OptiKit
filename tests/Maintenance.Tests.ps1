# Testes de manutenção: validação de exit code, propagação de falhas e cancelamento

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'src\windows\core\logger.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\core\backup.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\hardware-utils.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\winget-engine.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\tweak-engine.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\maintenance.ps1')
}

Describe 'Manutenção (maintenance.ps1)' {
    BeforeEach {
        $testRoot = Join-Path $TestDrive ("maintenance_test_" + [Guid]::NewGuid().ToString('N'))
        Initialize-OptiKitEnvironment -DataRoot $testRoot -DryRun:$false | Out-Null
        $script:OptiKit.CancelRequest = $false
    }

    It 'Invoke-NativeStep deve aceitar exit code 0 e rejeitar exit code diferente de zero' {
        { Invoke-NativeStep -FilePath 'cmd.exe' -ArgumentList @('/c', 'exit', '0') -StepName 'Teste OK' } | Should -Not -Throw
        { Invoke-NativeStep -FilePath 'cmd.exe' -ArgumentList @('/c', 'exit', '3') -StepName 'Teste Falha' } | Should -Throw '*código de saída 3*'
    }

    It 'Invoke-CancelableProcess deve aceitar códigos de sucesso explícitos (ex.: 3010)' {
        (Invoke-CancelableProcess -FilePath 'cmd.exe' -Arguments '/c exit 3010' -StepName 'Teste 3010' -SuccessExitCodes @(0, 3010)) | Should -BeTrue
        (Invoke-CancelableProcess -FilePath 'cmd.exe' -Arguments '/c exit 3010' -StepName 'Teste 3010' -SuccessExitCodes @(0)) | Should -BeFalse
    }

    It 'Clear-OptiKitDirectory deve remover arquivos e contabilizar bytes' {
        $dir = Join-Path $TestDrive 'cleanup_dir'
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'a.bin') -Value ('A' * 1024)
        Set-Content -LiteralPath (Join-Path $dir 'b.bin') -Value ('B' * 2048)

        $result = Clear-OptiKitDirectory -TargetDirectories @($dir)
        $result.DeletedFiles | Should -Be 2
        $result.FreedBytes | Should -BeGreaterThan 0
        @(Get-ChildItem -LiteralPath $dir -File).Count | Should -Be 0
    }

    It 'Invoke-AdvancedCleanup deve limpar caches informados sem executar ferramentas do sistema' {
        $wuDir = Join-Path $TestDrive 'wu_cache'
        $pfDir = Join-Path $TestDrive 'prefetch'
        New-Item -Path $wuDir -ItemType Directory -Force | Out-Null
        New-Item -Path $pfDir -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $wuDir 'update.bin') -Value ('U' * 1024)
        Set-Content -LiteralPath (Join-Path $pfDir 'app.pf') -Value ('P' * 512)

        Invoke-AdvancedCleanup -WindowsUpdateCache $wuDir -PrefetchDirectory $pfDir -SkipComponentStore -SkipDeliveryOptimization -SkipRecycleBin

        @(Get-ChildItem -LiteralPath $wuDir -File).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $pfDir -File).Count | Should -Be 0
        ($script:OptiKit.LogHistory -join "`n") | Should -Match 'Limpeza avançada concluída'
    }

    It 'Invoke-NetworkReset deve propagar falha de um passo nativo' {
        Mock Invoke-NativeStep {
            if ($StepName -eq 'Reset do Winsock') {
                throw 'falha simulada no Winsock'
            }
        }

        { Invoke-NetworkReset } | Should -Throw '*falha simulada no Winsock*'
        Should -Invoke Invoke-NativeStep -Times 2 -Exactly
    }

    It 'Invoke-SystemIntegrityRepair deve falhar alto quando o DISM falha' {
        Mock Invoke-CancelableProcess { $false }

        { Invoke-SystemIntegrityRepair } | Should -Throw '*DISM /RestoreHealth falhou*'
        Should -Invoke Invoke-CancelableProcess -Times 1 -Exactly
    }

    It 'Invoke-SystemIntegrityRepair deve falhar alto quando o SFC falha' {
        $script:processCalls = 0
        Mock Invoke-CancelableProcess {
            $script:processCalls++
            return ($script:processCalls -eq 1)
        }

        { Invoke-SystemIntegrityRepair } | Should -Throw '*SFC /scannow retornou código de falha*'
        Should -Invoke Invoke-CancelableProcess -Times 2 -Exactly
    }

    It 'Invoke-SystemIntegrityRepair deve distinguir cancelamento de falha' {
        Mock Invoke-CancelableProcess {
            $script:OptiKit.CancelRequest = $true
            return $false
        }

        { Invoke-SystemIntegrityRepair } | Should -Throw '*cancelada pelo usuário durante o DISM*'
    }

    It 'Restart-OptiKitToUefi deve usar shutdown /fw quando o sistema é UEFI' {
        Mock Confirm-SecureBootUEFI { $true }
        Mock Invoke-NativeStep {}

        Restart-OptiKitToUefi

        Should -Invoke Invoke-NativeStep -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'shutdown.exe' -and ($ArgumentList -contains '/fw') -and ($ArgumentList -contains '/r')
        }
    }

    It 'Restart-OptiKitToUefi deve recusar quando não consegue confirmar UEFI' {
        Mock Confirm-SecureBootUEFI { throw 'não suportado' }
        Mock Invoke-NativeStep {}

        { Restart-OptiKitToUefi } | Should -Throw '*UEFI*'
        Should -Invoke Invoke-NativeStep -Times 0 -Exactly
    }
}
