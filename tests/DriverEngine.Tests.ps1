# Testes do inventário de drivers, links oficiais e backup via pnputil

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'src\windows\modules\driver-engine.ps1')
}

Describe 'Driver Engine (driver-engine.ps1)' {
    It 'Deve mapear fabricantes para os sites oficiais e retornar vazio quando desconhecido' {
        (Get-OptiKitDriverVendorLink -Manufacturer 'NVIDIA' -DeviceName 'GeForce RTX 4060') | Should -Match 'nvidia\.com'
        (Get-OptiKitDriverVendorLink -Manufacturer 'AMD' -DeviceName 'Radeon RX 6600') | Should -Match 'amd\.com'
        (Get-OptiKitDriverVendorLink -Manufacturer 'Intel' -DeviceName 'UHD Graphics') | Should -Match 'intel\.com'
        (Get-OptiKitDriverVendorLink -Manufacturer 'Realtek' -DeviceName 'Audio') | Should -BeNullOrEmpty
        (Get-OptiKitDriverVendorLink -Manufacturer 'Microsoft' -DeviceName 'Plug and Play Software Device Enumerator') | Should -BeNullOrEmpty
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
        ($items | Where-Object DeviceName -eq 'NVIDIA GeForce RTX 4060').HardwareID | Should -Be 'PCI\VEN_10DE'
        ($items | Where-Object DeviceName -eq 'Controlador desconhecido').Status | Should -Be 'Problema'
        @($items | Where-Object DeviceName -eq 'Dispositivo irrelevante').Count | Should -Be 0
    }

    It 'Deve converter uma atualização de driver em linha com versão atual e disponível' {
        $update = [pscustomobject]@{
            Type              = 2
            IsHidden          = $false
            BrowseOnly        = $false
            Title             = 'NVIDIA - Display - 32.0.15.7000'
            Description       = 'Driver de vídeo'
            DriverVerVersion  = '32.0.15.7000'
            DriverVerDate     = [datetime]'2026-02-01'
            DriverHardwareID  = 'PCI\VEN_10DE&DEV_2684'
            DriverProvider    = 'NVIDIA'
            MaxDownloadSize   = 800MB
            RebootRequired    = $true
            Identity          = [pscustomobject]@{ UpdateID = '11111111-1111-1111-1111-111111111111' }
        }
        $drivers = @([pscustomobject]@{
                DeviceName    = 'NVIDIA GeForce RTX 4060'
                DriverVersion = '32.0.15.6094'
                HardwareID    = 'PCI\VEN_10DE&DEV_2684'
            })

        $row = ConvertTo-OptiKitDriverUpdateRow -Update $update -Drivers $drivers
        $row.DeviceName | Should -Be 'NVIDIA GeForce RTX 4060'
        $row.CurrentVersion | Should -Be '32.0.15.6094'
        $row.AvailableVersion | Should -Be '32.0.15.7000'
        $row.Provider | Should -Be 'NVIDIA'
        $row.SizeMB | Should -Be 800
        $row.RebootRequired | Should -BeTrue
        $row.RebootText | Should -Be 'Sim'
        $row.OptionalText | Should -Be 'Não'
        $row.UpdateId | Should -Be '11111111-1111-1111-1111-111111111111'

        $small = [pscustomobject]@{
            Type             = 2
            IsHidden         = $false
            BrowseOnly       = $true
            Title            = 'Monitor - atualização pequena'
            Description      = ''
            DriverVerVersion = ''
            DriverVerDate    = [datetime]'2013-08-02'
            DriverHardwareID = 'monitor\dela088'
            DriverProvider   = 'Dell Inc.'
            MaxDownloadSize  = 25138
            RebootRequired   = $false
            Identity         = [pscustomobject]@{ UpdateID = '44444444-4444-4444-4444-444444444444' }
        }
        $smallRow = ConvertTo-OptiKitDriverUpdateRow -Update $small -Drivers @()
        $smallRow.CurrentVersion | Should -Be '—'
        $smallRow.AvailableVersion | Should -Be '—'
        $smallRow.SizeText | Should -Be '25 KB'
        $smallRow.OptionalText | Should -Be 'Sim'

        $monitorDrivers = @([pscustomobject]@{
                DeviceName    = 'Generic Monitor (DELL P1913)'
                DriverVersion = '10.0.19041.1'
                HardwareID    = 'DISPLAY\DELA088\7&3842E1A4&0&UID516'
            })
        $monitorRow = ConvertTo-OptiKitDriverUpdateRow -Update $small -Drivers $monitorDrivers
        $monitorRow.DeviceName | Should -Be 'Generic Monitor (DELL P1913)'
        $monitorRow.CurrentVersion | Should -Be '10.0.19041.1'
    }

    It 'Deve ignorar atualizações ocultas e que não sejam de driver' {
        $hidden = [pscustomobject]@{
            Type       = 2
            IsHidden   = $true
            Title      = 'Driver oculto'
            Identity   = [pscustomobject]@{ UpdateID = '22222222-2222-2222-2222-222222222222' }
        }
        $software = [pscustomobject]@{
            Type       = 1
            IsHidden   = $false
            Title      = 'Atualização de software'
            Identity   = [pscustomobject]@{ UpdateID = '33333333-3333-3333-3333-333333333333' }
        }

        ConvertTo-OptiKitDriverUpdateRow -Update $hidden | Should -BeNullOrEmpty
        ConvertTo-OptiKitDriverUpdateRow -Update $software | Should -BeNullOrEmpty
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
