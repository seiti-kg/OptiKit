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
}
