# Testes do Winget Upgrade: construção de comandos, sucesso, falha e DryRun

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'src\windows\core\logger.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\core\backup.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\hardware-utils.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\winget-engine.ps1')
}

Describe 'Winget Upgrade (winget-engine.ps1)' {
    BeforeEach {
        $testRoot = Join-Path $TestDrive ("winget_test_" + [Guid]::NewGuid().ToString('N'))
        Initialize-OptiKitEnvironment -DataRoot $testRoot -DryRun:$false | Out-Null
        Mock Test-WingetAvailable {
            [pscustomobject]@{ Available = $true; Path = 'winget.exe'; Version = '1.6.0'; IsHealthy = $true }
        }
        Mock Invoke-OptiKitWingetCommand { 0 }
    }

    It 'Deve atualizar todos os apps com --all e --include-unknown' {
        (Invoke-OptiKitWingetUpgrade -All) | Should -BeTrue
        Should -Invoke Invoke-OptiKitWingetCommand -Times 1 -Exactly -ParameterFilter {
            ($Arguments -contains 'upgrade') -and ($Arguments -contains '--all') -and ($Arguments -contains '--include-unknown')
        }
    }

    It 'Deve atualizar IDs específicos mantendo --exact' {
        (Invoke-OptiKitWingetUpgrade -Ids @('Microsoft.PowerToys', 'Mozilla.Firefox')) | Should -BeTrue
        Should -Invoke Invoke-OptiKitWingetCommand -Times 2 -Exactly -ParameterFilter {
            ($Arguments -contains 'upgrade') -and ($Arguments -contains '--exact')
        }
        Should -Invoke Invoke-OptiKitWingetCommand -Times 1 -Exactly -ParameterFilter {
            $Arguments -contains 'Microsoft.PowerToys'
        }
        Should -Invoke Invoke-OptiKitWingetCommand -Times 1 -Exactly -ParameterFilter {
            $Arguments -contains 'Mozilla.Firefox'
        }
    }

    It 'Deve falhar quando o Winget retorna código inesperado' {
        Mock Invoke-OptiKitWingetCommand { 1 }
        { Invoke-OptiKitWingetUpgrade -All } | Should -Throw '*código 1*'
    }

    It 'Deve aceitar "nenhuma atualização" e reboot pendente como sucesso' {
        Mock Invoke-OptiKitWingetCommand { -1978335189 }
        (Invoke-OptiKitWingetUpgrade -All) | Should -BeTrue

        Mock Invoke-OptiKitWingetCommand { 3010 }
        (Invoke-OptiKitWingetUpgrade -All) | Should -BeTrue
    }

    It 'Deve exigir -All ou -Ids' {
        { Invoke-OptiKitWingetUpgrade } | Should -Throw '*Informe -All*'
    }

    It 'Não deve consultar o Winget em DryRun' {
        $testRoot = Join-Path $TestDrive ("winget_dry_" + [Guid]::NewGuid().ToString('N'))
        Initialize-OptiKitEnvironment -DataRoot $testRoot -DryRun:$true | Out-Null
        (Invoke-OptiKitWingetUpgrade -All) | Should -BeTrue
        Should -Invoke Test-WingetAvailable -Times 0 -Exactly
        Should -Invoke Invoke-OptiKitWingetCommand -Times 0 -Exactly
    }
}
