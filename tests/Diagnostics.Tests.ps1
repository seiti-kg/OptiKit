# Testes dos diagnósticos somente leitura: BIOS/TPM, disco, estabilidade, reboot pendente e Defender

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'src\windows\core\logger.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\core\backup.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\hardware-utils.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\winget-engine.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\tweak-engine.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\maintenance.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\diagnostics.ps1')
}

Describe 'Diagnósticos estendidos (diagnostics.ps1)' {
    BeforeEach {
        $testRoot = Join-Path $TestDrive ("diagnostics_test_" + [Guid]::NewGuid().ToString('N'))
        Initialize-OptiKitEnvironment -DataRoot $testRoot -DryRun:$false | Out-Null
    }

    It 'Deve reportar BIOS/UEFI, Secure Boot e TPM' {
        Mock Get-CimInstance {
            if ($ClassName -eq 'Win32_BIOS') {
                [pscustomobject]@{ Manufacturer = 'ASUS'; SMBIOSBIOSVersion = '1.2.3'; ReleaseDate = [datetime]'2025-01-01' }
            }
            elseif ($ClassName -eq 'Win32_ComputerSystem') {
                [pscustomobject]@{ Manufacturer = 'ASUS'; Model = 'ROG X670E' }
            }
        }
        Mock Confirm-SecureBootUEFI { $true }
        Mock Get-Tpm { [pscustomobject]@{ TpmPresent = $true; TpmReady = $true; SpecVersion = '2.0' } }

        $item = Get-OptiKitDiagnosticBios
        $item.Status | Should -Be 'OK'
        $item.Summary | Should -Match 'Secure Boot ativo'
        $item.Summary | Should -Match 'TPM 2.0 pronto'
        $item.Detail | Should -Match 'BIOS 1.2.3'
    }

    It 'Deve avisar quando Secure Boot ou TPM não está pronto' {
        Mock Get-CimInstance {
            if ($ClassName -eq 'Win32_BIOS') { [pscustomobject]@{ Manufacturer = 'ASUS'; SMBIOSBIOSVersion = '1.2.3'; ReleaseDate = [datetime]'2025-01-01' } }
            elseif ($ClassName -eq 'Win32_ComputerSystem') { [pscustomobject]@{ Manufacturer = 'ASUS'; Model = 'ROG X670E' } }
        }
        Mock Confirm-SecureBootUEFI { $false }
        Mock Get-Tpm { [pscustomobject]@{ TpmPresent = $false; TpmReady = $false; SpecVersion = '2.0' } }

        $item = Get-OptiKitDiagnosticBios
        $item.Status | Should -Be 'Warn'
        $item.Summary | Should -Match 'Secure Boot desativado'
        $item.Summary | Should -Match 'TPM ausente'
    }

    It 'Deve reportar saúde e desgaste dos discos' {
        $disks = @([pscustomobject]@{
            FriendlyName      = 'NVMe Teste'
            MediaType         = 'SSD'
            HealthStatus      = 'Healthy'
            OperationalStatus = 'OK'
            Size              = 500GB
            DeviceId          = '0'
        })

        $item = Get-OptiKitDiagnosticDisk -Disks $disks -ReliabilityCounters @{ '0' = [pscustomobject]@{ Wear = 12 } } -SystemVolume ([pscustomobject]@{ SizeRemaining = 100GB; Size = 500GB })
        $item.Status | Should -Be 'OK'
        $item.Detail | Should -Match 'NVMe Teste'
        $item.Detail | Should -Match 'desgaste 12%'
    }

    It 'Deve avisar quando o SSD está muito desgastado' {
        $disks = @([pscustomobject]@{
            FriendlyName      = 'SSD Antigo'
            MediaType         = 'SSD'
            HealthStatus      = 'Healthy'
            OperationalStatus = 'OK'
            Size              = 240GB
            DeviceId          = '0'
        })

        $item = Get-OptiKitDiagnosticDisk -Disks $disks -ReliabilityCounters @{ '0' = [pscustomobject]@{ Wear = 90 } } -SystemVolume ([pscustomobject]@{ SizeRemaining = 100GB; Size = 500GB })
        $item.Status | Should -Be 'Warn'
        $item.Summary | Should -Match 'desgaste 90%'
    }

    It 'Deve montar os detalhes de saúde de um SSD NVMe' {
        $disk = [pscustomobject]@{
            DeviceId          = '2'
            FriendlyName      = 'KINGSTON SNV2S1000G'
            MediaType         = 'SSD'
            BusType           = 'NVMe'
            Size              = 1000204886016
            HealthStatus      = 'Healthy'
            OperationalStatus = @('OK')
            SerialNumber      = 'SERIAL'
            FirmwareVersion   = 'SBM02103'
            PhysicalLocation  = 'Integrated : Bus 1'
        }
        $logical = [pscustomobject]@{ Number = 2; IsBoot = $true; IsSystem = $true }
        $counter = [pscustomobject]@{
            Temperature            = 39
            TemperatureMax         = 70
            Wear                   = 5
            PowerOnHours           = 8667
            StartStopCycleCount    = 1386
            ReadErrorsUncorrected  = 0
            WriteErrorsUncorrected = 0
        }

        $row = ConvertTo-OptiKitStorageHealthRow -Disk $disk -LogicalDisk $logical -Counter $counter
        $row.HealthText | Should -Be 'OK'
        $row.Severity | Should -Be 'OK'
        $row.TypeText | Should -Be 'SSD NVMe'
        $row.TemperatureText | Should -Be '39 °C'
        $row.WearText | Should -Be '5%'
        $row.HealthPercentText | Should -Be '95%'
        $row.PowerOnText | Should -Be ('{0:N0} h' -f 8667)
        $row.PowerCyclesText | Should -Be ('{0:N0}' -f 1386)
        $row.Detail | Should -Match 'KINGSTON SNV2S1000G'
        $row.Detail | Should -Match 'Sistema: Sim'

        $warning = ConvertTo-OptiKitStorageHealthRow -Disk $disk -LogicalDisk $logical -Counter ([pscustomobject]@{ Temperature = 75; TemperatureMax = 80; Wear = 5; ReadErrorsUncorrected = 2; WriteErrorsUncorrected = 0 })
        $warning.HealthText | Should -Be 'Atenção'
        $warning.Severity | Should -Be 'Warn'

        $criticalDisk = $disk.PSObject.Copy()
        $criticalDisk.HealthStatus = 'Unhealthy'
        $critical = ConvertTo-OptiKitStorageHealthRow -Disk $criticalDisk -LogicalDisk $logical -Counter $counter
        $critical.HealthText | Should -Be 'Crítico'
        $critical.Severity | Should -Be 'Error'

        $nvme = [pscustomobject]@{
            PercentageUsed          = 3
            HealthPercent           = 97
            TemperatureC            = 41
            PowerOnHours            = 8873
            PowerCycles             = 1387
            UnsafeShutdowns         = 425
            MediaErrors             = 0
            AvailableSpare          = 100
            AvailableSpareThreshold = 10
            HostReadCommands        = 1880179683
            HostWrittenCommands     = 1255866976
        }
        $nvmeRow = ConvertTo-OptiKitStorageHealthRow -Disk $disk -LogicalDisk $logical -Counter $counter -NvmeHealth $nvme
        $nvmeRow.HealthPercentText | Should -Be '97%'
        $nvmeRow.WearText | Should -Be '3%'
        $nvmeRow.TemperatureText | Should -Be '41 °C'
        $nvmeRow.Detail | Should -Match 'NVMe usado: 3%'
        $nvmeRow.NvmeUnsafeShutdowns | Should -Be 425
    }

    It 'Deve enumerar discos mesmo quando os contadores não estão disponíveis' {
        $disk = [pscustomobject]@{
            DeviceId          = '2'
            FriendlyName      = 'SSD Teste'
            MediaType         = 'SSD'
            BusType           = 'NVMe'
            Size              = 500GB
            HealthStatus      = 'Healthy'
            OperationalStatus = @('OK')
            SerialNumber      = 'SERIAL'
            FirmwareVersion   = '1.0'
        }
        $logical = @([pscustomobject]@{ Number = 2; IsBoot = $true; IsSystem = $true })
        $counter = [pscustomobject]@{ Temperature = 39; TemperatureMax = 70; Wear = 5; PowerOnHours = 10; StartStopCycleCount = 2 }

        $rows = @(Get-OptiKitStorageHealth -PhysicalDisks @($disk) -LogicalDisks $logical -ReliabilityCounters @{ '2' = $counter } -NvmeHealth @{ '2' = $null })
        $rows.Count | Should -Be 1
        $rows[0].Name | Should -Be 'SSD Teste'
        $rows[0].TemperatureText | Should -Be '39 °C'

        $withoutCounters = @(Get-OptiKitStorageHealth -PhysicalDisks @($disk) -LogicalDisks $logical -ReliabilityCounters @{ '2' = $null } -NvmeHealth @{ '2' = $null })
        $withoutCounters.Count | Should -Be 1
        $withoutCounters[0].TemperatureText | Should -Be '—'
    }

    It 'Deve reportar erros WHEA como problema de estabilidade' {
        Mock Get-WinEvent {
            if ($FilterHashtable.ProviderName -eq 'Microsoft-Windows-WHEA-Logger') {
                @([pscustomobject]@{ TimeCreated = Get-Date })
            }
            else {
                @()
            }
        }

        $item = Get-OptiKitDiagnosticStability
        $item.Status | Should -Be 'Error'
        $item.Summary | Should -Match 'WHEA'
    }

    It 'Deve detectar reinicialização pendente' {
        Mock Test-Path { $true }
        Mock Get-ItemProperty { $null }

        $item = Get-OptiKitDiagnosticPendingReboot
        $item.Status | Should -Be 'Warn'
        $item.Detail | Should -Match 'Windows Update'
    }

    It 'Deve reportar Defender ativo e atualizado' {
        Mock Get-MpComputerStatus {
            [pscustomobject]@{ AntivirusEnabled = $true; RealTimeProtectionEnabled = $true; AntivirusSignatureAge = 2 }
        }

        $item = Get-OptiKitDiagnosticDefender
        $item.Status | Should -Be 'OK'
        $item.Detail | Should -Match 'Assinaturas com 2 dia'
    }
}

Describe 'Diagnósticos de gaming (VRAM, janela e energia)' {
    BeforeEach {
        $testRoot = Join-Path $TestDrive ("gaming_diagnostics_" + [Guid]::NewGuid().ToString('N'))
        Initialize-OptiKitEnvironment -DataRoot $testRoot -DryRun:$false | Out-Null
    }

    It 'Deve avisar quando HAGS está ativo em GPU de 8 GB' {
        Mock Get-RegistryEntryState {
            param($Path, $Name, $FallbackType)
            switch ($Name) {
                'HwSchMode' { [pscustomobject]@{ ValueExisted = $true; Value = 2 } }
                'AutoGameModeEnabled' { [pscustomobject]@{ ValueExisted = $true; Value = 1 } }
                'AllowAutoGameMode' { [pscustomobject]@{ ValueExisted = $true; Value = 1 } }
                default { [pscustomobject]@{ ValueExisted = $false; Value = $null } }
            }
        }
        Mock Get-ActivePowerPlanGuid { '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }
        Mock Get-OptiKitHardware { [pscustomobject]@{ IsX3D = $false; IsLaptop = $false; GpuVramGB = 8 } }

        $item = Get-OptiKitDiagnosticGamingToggles
        $item.Status | Should -Be 'Warn'
        $item.Detail | Should -Match 'VRAM'
    }

    It 'Deve considerar HAGS OK em GPU de 16 GB' {
        Mock Get-RegistryEntryState {
            param($Path, $Name, $FallbackType)
            switch ($Name) {
                'HwSchMode' { [pscustomobject]@{ ValueExisted = $true; Value = 2 } }
                'AutoGameModeEnabled' { [pscustomobject]@{ ValueExisted = $true; Value = 1 } }
                'AllowAutoGameMode' { [pscustomobject]@{ ValueExisted = $true; Value = 1 } }
                default { [pscustomobject]@{ ValueExisted = $false; Value = $null } }
            }
        }
        Mock Get-ActivePowerPlanGuid { '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }
        Mock Get-OptiKitHardware { [pscustomobject]@{ IsX3D = $false; IsLaptop = $false; GpuVramGB = 16 } }

        $item = Get-OptiKitDiagnosticGamingToggles
        $item.Status | Should -Be 'OK'
    }

    It 'Deve avisar sobre otimizações de janela desativadas e economia de energia ativa' {
        Mock Test-OptiKitWindowedGameOptimizations { $false }
        Mock Get-OptiKitEnergySaverState { $true }

        $item = Get-OptiKitDiagnosticWindowsGamingState
        $item.Status | Should -Be 'Warn'
        $item.Summary | Should -Match 'janela'
        $item.Summary | Should -Match 'energia'
    }

    It 'Deve considerar otimizações de janela e energia OK' {
        Mock Test-OptiKitWindowedGameOptimizations { $true }
        Mock Get-OptiKitEnergySaverState { $false }

        $item = Get-OptiKitDiagnosticWindowsGamingState
        $item.Status | Should -Be 'OK'
    }
}

Describe 'Recomendações por hardware' {
    BeforeEach {
        $testRoot = Join-Path $TestDrive ("hardware_recommendations_" + [Guid]::NewGuid().ToString('N'))
        Initialize-OptiKitEnvironment -DataRoot $testRoot -DryRun:$false | Out-Null
    }

    It 'Deve recomendar GPU dedicada, dual-channel e revisão do HAGS' {
        Mock Get-OptiKitHardware {
            [pscustomobject]@{
                HasHybridGraphics = $true
                GpuVramGB         = 8
                RamModuleCount    = 1
                GpuDetails        = @(
                    [pscustomobject]@{ Name = 'AMD Radeon(TM) Graphics'; Kind = 'Integrated' },
                    [pscustomobject]@{ Name = 'AMD Radeon RX 6600'; Kind = 'Discrete' }
                )
            }
        }
        Mock Get-RegistryEntryState { [pscustomobject]@{ ValueExisted = $true; Value = 2 } }

        $item = Get-OptiKitDiagnosticHardwareRecommendations
        $item.Status | Should -Be 'Warn'
        $item.Summary | Should -Match 'híbridas'
        $item.Summary | Should -Match 'single-channel'
        $item.Summary | Should -Match 'HAGS'
        $item.Detail | Should -Match 'RX 6600'
    }

    It 'Deve retornar OK quando não há recomendação específica' {
        Mock Get-OptiKitHardware {
            [pscustomobject]@{
                HasHybridGraphics = $false
                GpuVramGB         = 16
                RamModuleCount    = 2
                GpuDetails        = @([pscustomobject]@{ Name = 'AMD Radeon RX 6600'; Kind = 'Discrete' })
            }
        }
        Mock Get-RegistryEntryState { [pscustomobject]@{ ValueExisted = $false; Value = $null } }

        $item = Get-OptiKitDiagnosticHardwareRecommendations
        $item.Status | Should -Be 'OK'
    }
}
