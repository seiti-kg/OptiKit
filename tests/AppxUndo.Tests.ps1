# Testes de Apply/Undo de pacotes Appx (tweak-engine.ps1)

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'src\windows\core\logger.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\core\backup.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\winget-engine.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\hardware-utils.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\tweak-engine.ps1')
}

Describe 'Appx Undo/Apply (tweak-engine.ps1)' {
    BeforeEach {
        $testDataDir = Join-Path $TestDrive ("appx_test_" + [Guid]::NewGuid().ToString('N'))
        Initialize-OptiKitEnvironment -DataRoot $testDataDir -DryRun:$false | Out-Null
        New-OptiKitBackupSession -SessionId '2026-11-04_12-00-00' | Out-Null

        $script:MockAppxTweak = [pscustomobject]@{
            title          = 'Teste Appx'
            registry       = @()
            services       = @()
            scheduledTasks = @()
            appx           = @([pscustomobject]@{ name = 'Microsoft.TestAppx'; storeId = '9TESTSTORE' })
            invokeScript   = @()
            undoScript     = @()
        }
    }

    It 'Deve pular a reinstalação Appx no Undo quando o pacote não existia antes (existed = $false)' {
        Save-CapturedState -Id 'AppxSkip' -CapturedItems @(
            @{ kind = 'appx'; name = 'Microsoft.TestAppx'; storeId = '9TESTSTORE'; existed = $false }
        ) | Out-Null

        Mock Invoke-AppxRemoval { }

        Invoke-Tweak -Id 'AppxSkip' -Tweak $script:MockAppxTweak -Mode 'Undo' | Out-Null

        Should -Invoke Invoke-AppxRemoval -Times 0 -Exactly
        (Get-CapturedState -Id 'AppxSkip') | Should -BeNullOrEmpty
    }

    It 'Deve reinstalar o Appx no Undo uma única vez quando o pacote existia antes (existed = $true)' {
        Save-CapturedState -Id 'AppxRestore' -CapturedItems @(
            @{ kind = 'appx'; name = 'Microsoft.TestAppx'; storeId = '9TESTSTORE'; existed = $true }
        ) | Out-Null

        Mock Invoke-AppxRemoval { }

        Invoke-Tweak -Id 'AppxRestore' -Tweak $script:MockAppxTweak -Mode 'Undo' | Out-Null

        Should -Invoke Invoke-AppxRemoval -Times 1 -Exactly -ParameterFilter {
            $PackageName -eq 'Microsoft.TestAppx' -and $StoreId -eq '9TESTSTORE' -and $Mode -eq 'Undo'
        }
    }

    It 'Deve lançar no Undo quando o Winget retorna código de saída diferente de 0' {
        Mock Test-WingetAvailable {
            [pscustomobject]@{ Available = $true; Path = 'C:\fake\winget.exe'; Version = 'v1.7.0'; IsHealthy = $true }
        }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 1 } }
        Mock Get-AppxPackage { $null }

        { Invoke-AppxRemoval -PackageName 'Microsoft.TestAppx' -StoreId '9TESTSTORE' -Mode 'Undo' } |
            Should -Throw '*Código de saída: 1*'

        Should -Invoke Start-Process -Times 1 -Exactly
        Should -Invoke Get-AppxPackage -Times 0 -Exactly
    }

    It 'Deve lançar no Undo quando o pacote não é encontrado após o Winget retornar sucesso' {
        Mock Test-WingetAvailable {
            [pscustomobject]@{ Available = $true; Path = 'C:\fake\winget.exe'; Version = 'v1.7.0'; IsHealthy = $true }
        }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        Mock Get-AppxPackage { $null }

        { Invoke-AppxRemoval -PackageName 'Microsoft.TestAppx' -StoreId '9TESTSTORE' -Mode 'Undo' } |
            Should -Throw '*não encontrado após a reinstalação*'
    }

    It 'Deve lançar no Undo quando o Store ID está vazio' {
        Mock Test-WingetAvailable {
            [pscustomobject]@{ Available = $true; Path = 'C:\fake\winget.exe'; Version = 'v1.7.0'; IsHealthy = $true }
        }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

        { Invoke-AppxRemoval -PackageName 'Microsoft.TestAppx' -StoreId '' -Mode 'Undo' } |
            Should -Throw '*Store ID vazio*'

        Should -Invoke Start-Process -Times 0 -Exactly
        Should -Invoke Test-WingetAvailable -Times 0 -Exactly
    }

    It 'Deve preservar o estado capturado quando a reinstalação Appx falha no Undo' {
        Save-CapturedState -Id 'AppxFail' -CapturedItems @(
            @{ kind = 'appx'; name = 'Microsoft.TestAppx'; storeId = '9TESTSTORE'; existed = $true }
        ) | Out-Null

        Mock Test-WingetAvailable {
            [pscustomobject]@{ Available = $true; Path = 'C:\fake\winget.exe'; Version = 'v1.7.0'; IsHealthy = $true }
        }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 1 } }
        Mock Get-AppxPackage { $null }

        { Invoke-Tweak -Id 'AppxFail' -Tweak $script:MockAppxTweak -Mode 'Undo' } | Should -Throw

        $record = Get-CapturedState -Id 'AppxFail'
        $record | Should -Not -BeNullOrEmpty
        @($record.captured)[0].existed | Should -BeTrue
    }

    It 'Deve bloquear a remoção do app de Configurações e da dependência UI.Xaml.CBS' {
        { Invoke-AppxRemoval -PackageName 'windows.immersivecontrolpanel' -StoreId '' -Mode 'Apply' } | Should -Throw '*protegido*'
        { Invoke-AppxRemoval -PackageName 'Microsoft.UI.Xaml.CBS' -StoreId '' -Mode 'Apply' } | Should -Throw '*protegido*'
    }
}
