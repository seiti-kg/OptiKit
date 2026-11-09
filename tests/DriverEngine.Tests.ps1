# Testes do inventário de drivers, links oficiais e backup via pnputil

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'src\windows\modules\driver-engine.ps1')
}

Describe 'Driver Engine (driver-engine.ps1)' {
    It 'Deve mapear fabricantes para os sites oficiais e Windows Update' {
        (Get-OptiKitDriverVendorLink -Manufacturer 'NVIDIA' -DeviceName 'GeForce RTX 4060') | Should -Match 'nvidia\.com'
        (Get-OptiKitDriverVendorLink -Manufacturer 'AMD' -DeviceName 'Radeon RX 6600') | Should -Match 'amd\.com'
        (Get-OptiKitDriverVendorLink -Manufacturer 'Intel' -DeviceName 'UHD Graphics') | Should -Match 'intel\.com'
        (Get-OptiKitDriverVendorLink -Manufacturer 'Realtek' -DeviceName 'Audio') | Should -Be 'ms-settings:windowsupdate'
    }

    It 'Deve inventariar drivers relevantes e marcar dispositivos com problema' {
        Mock Get-CimInstance {
            param($ClassName)
            if ($ClassName -eq 'Win32_PnPSignedDriver') {
                @(
                    [pscustomobject]@{
                        DeviceName = 'NVIDIA GeForce RTX 4060'
                        DeviceClass = 'Display'
                        DriverVersion = '32.0.15.6094'
                        DriverDate = [datetime]'2026-01-10'
                        Manufacturer = 'NVIDIA'
                        DeviceID = 'PCI\VEN_10DE'
                    },
                    [pscustomobject]@{
                        DeviceName = 'Dispositivo irrelevante'
                        DeviceClass = 'Battery'
                        DriverVersion = '1.0'
                        DriverDate = [datetime]'2026-01-10'
                        Manufacturer = 'Teste'
                        DeviceID = 'ACPI\TEST'
                    }
                )
            }
            elseif ($ClassName -eq 'Win32_PnPEntity') {
                @([pscustomobject]@{
                    Name = 'Controlador desconhecido'
                    DeviceClass = 'USB'
                    Manufacturer = 'Desconhecido'
                    ConfigManagerErrorCode = 28
                })
            }
        }

        $items = @(Get-OptiKitDriverInventory)
        $items.Count | Should -Be 2
        ($items | Where-Object DeviceName -eq 'NVIDIA GeForce RTX 4060').Status | Should -Be 'OK'
        ($items | Where-Object DeviceName -eq 'Controlador desconhecido').Status | Should -Be 'Problema'
        @($items | Where-Object DeviceName -eq 'Dispositivo irrelevante').Count | Should -Be 0
    }

    It 'Deve chamar pnputil e falhar quando o backup retorna erro' {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        $destination = Join-Path $TestDrive 'drivers-backup'
        (Export-OptiKitDrivers -Destination $destination) | Should -Be $destination
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -like '*pnputil.exe' -and ($ArgumentList -contains '/export-driver')
        }

        Mock Start-Process { [pscustomobject]@{ ExitCode = 1 } }
        { Export-OptiKitDrivers -Destination (Join-Path $TestDrive 'drivers-fail') } | Should -Throw '*pnputil falhou*'
    }
}
