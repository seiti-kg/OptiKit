# Testes das ferramentas de processos: proteção e lista de apps com janela

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'src\windows\modules\process-tools.ps1')
}

Describe 'Process Tools (process-tools.ps1)' {
    It 'Deve proteger shell, anti-cheat, serviços e o próprio OptiKit' {
        (Test-OptiKitProtectedProcess -Name 'explorer') | Should -BeTrue
        (Test-OptiKitProtectedProcess -Name 'RiotClientServices') | Should -BeTrue
        (Test-OptiKitProtectedProcess -Name 'vgc') | Should -BeTrue
        (Test-OptiKitProtectedProcess -Name 'MsMpEng') | Should -BeTrue
        (Test-OptiKitProtectedProcess -Name 'OptiKit') | Should -BeTrue
        (Test-OptiKitProtectedProcess -Name 'notepad') | Should -BeFalse
        (Test-OptiKitProtectedProcess -Name 'Discord') | Should -BeFalse
        (Test-OptiKitProtectedProcess -Name 'brave') | Should -BeFalse
    }

    It 'Deve listar somente processos permitidos com janela' {
        $session = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
        Mock Get-Process {
            @(
                [pscustomobject]@{ Id = 100; ProcessName = 'explorer'; MainWindowHandle = 10; MainWindowTitle = 'Explorer'; WorkingSet64 = 80MB; SessionId = $session },
                [pscustomobject]@{ Id = 101; ProcessName = 'notepad'; MainWindowHandle = 11; MainWindowTitle = 'Bloco de Notas'; WorkingSet64 = 20MB; SessionId = $session },
                [pscustomobject]@{ Id = 102; ProcessName = 'brave'; MainWindowHandle = 0; MainWindowTitle = ''; WorkingSet64 = 500MB; SessionId = $session }
            )
        }

        $items = @(Get-OptiKitBackgroundProcesses)
        $items.Count | Should -Be 1
        $items[0].Name | Should -Be 'notepad'
    }

    It 'Deve recusar suspensão de processo protegido antes de abrir o handle' {
        Mock Get-Process { [pscustomobject]@{ Id = 100; ProcessName = 'explorer'; MainWindowHandle = 10 } }
        { Suspend-OptiKitProcess -Id 100 } | Should -Throw '*protegido*'
    }
}
