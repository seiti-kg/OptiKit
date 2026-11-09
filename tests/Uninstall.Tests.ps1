# Testes do inventário e dos comandos do desinstalador

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'src\windows\modules\uninstall-engine.ps1')
}

Describe 'Uninstall Engine (uninstall-engine.ps1)' {
    It 'Deve filtrar componentes de sistema e atualizações do registro' {
        $normal = [pscustomobject]@{
            PSChildName    = 'AppNormal'
            DisplayName    = 'Aplicativo Normal'
            DisplayVersion = '1.0'
            Publisher      = 'Teste'
            EstimatedSize  = 2048
            UninstallString = 'C:\Teste\uninstall.exe'
        }
        (ConvertFrom-OptiKitRegistryEntry -Entry $normal -Key 'AppNormal') | Should -Not -BeNullOrEmpty

        $system = [pscustomobject]@{ DisplayName = 'Driver'; SystemComponent = 1 }
        (ConvertFrom-OptiKitRegistryEntry -Entry $system -Key 'Driver') | Should -BeNullOrEmpty

        $update = [pscustomobject]@{ DisplayName = 'KB5031234'; SystemComponent = 0 }
        (ConvertFrom-OptiKitRegistryEntry -Entry $update -Key 'KB5031234') | Should -BeNullOrEmpty

        $protected = [pscustomobject]@{ DisplayName = 'Microsoft.WindowsStore'; SystemComponent = 0 }
        (ConvertFrom-OptiKitRegistryEntry -Entry $protected -Key 'Store') | Should -BeNullOrEmpty
    }

    It 'Deve ignorar Appx de framework e o app de Configurações' {
        $framework = [pscustomobject]@{ Name = 'Microsoft.VCLibs.140.00'; IsFramework = $true; SignatureKind = 'Store'; PackageFullName = 'x'; Version = '1'; Publisher = 'Microsoft' }
        (ConvertFrom-OptiKitAppxPackage -Package $framework) | Should -BeNullOrEmpty

        $settings = [pscustomobject]@{ Name = 'windows.immersivecontrolpanel'; IsFramework = $false; SignatureKind = 'System'; PackageFullName = 'x'; Version = '1'; Publisher = 'Microsoft' }
        (ConvertFrom-OptiKitAppxPackage -Package $settings) | Should -BeNullOrEmpty
    }

    It 'Deve converter um MSI em desinstalação silenciosa com código de reboot aceito' {
        $program = [pscustomobject]@{
            Source          = 'Registry'
            DisplayName     = 'App MSI'
            UninstallString = 'MsiExec.exe /I{12345678-1234-1234-1234-1234567890AB}'
        }
        $command = Get-OptiKitUninstallCommand -Program $program
        $command.File | Should -Be 'msiexec.exe'
        $command.Arguments | Should -Contain '/x'
        $command.Arguments | Should -Contain '{12345678-1234-1234-1234-1234567890AB}'
        $command.Arguments | Should -Contain '/qb'
        $command.Arguments | Should -Contain '/norestart'
    }

    It 'Deve deduplicar programas de registro e Appx na listagem' {
        $entry = [pscustomobject]@{
            PSChildName    = 'AppNormal'
            DisplayName    = 'Aplicativo Normal'
            DisplayVersion = '1.0'
            Publisher      = 'Teste'
            EstimatedSize  = 0
        }
        $appx = [pscustomobject]@{
            Name            = 'Aplicativo Appx'
            IsFramework     = $false
            SignatureKind   = 'Store'
            PackageFullName = 'Aplicativo.Appx_1.0_x64__teste'
            Version         = '1.0'
            Publisher       = 'CN=Teste'
            InstallLocation = 'C:\Apps\Teste'
        }
        Mock Get-ItemProperty { @([pscustomobject]$entry) }
        Mock Get-AppxPackage { @([pscustomobject]$appx) }

        $programs = @(Get-OptiKitInstalledPrograms)
        $programs.Count | Should -Be 2
        @($programs | Where-Object DisplayName -eq 'Aplicativo Normal').Count | Should -Be 1
        @($programs | Where-Object DisplayName -eq 'Aplicativo Appx').Count | Should -Be 1
    }
}
