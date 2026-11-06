# Diagnóstico de Hardware (somente leitura): RAM/XMP, monitor, VBS/HVCI, HAGS/Game Mode/plano, X3D e driver de GPU

#region dev-only
if (-not (Get-Command Write-OptimizerLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\core\logger.ps1')
}
if (-not (Get-Command Get-OptiKitHardware -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'hardware-utils.ps1')
}
if (-not (Get-Command Get-RegistryEntryState -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'tweak-engine.ps1')
}
#endregion

function New-OptiKitDiagnosticItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][ValidateSet('OK', 'Warn', 'Error', 'Info', 'Unknown')][string]$Status,
        [Parameter(Mandatory = $true)][string]$Summary,
        [string]$Detail,
        [string]$ActionText,
        [string]$ActionUrl
    )

    return [pscustomobject]@{
        Id         = $Id
        Title      = $Title
        Status     = $Status
        Summary    = $Summary
        Detail     = $Detail
        ActionText = $ActionText
        ActionUrl  = $ActionUrl
    }
}

function Get-OptiKitDiagnosticRam {
    [CmdletBinding()]
    param()

    try {
        $modules = @(Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop)
        if ($modules.Count -eq 0) {
            return New-OptiKitDiagnosticItem -Id 'RamXmp' -Title 'Memória RAM (XMP/EXPO)' -Status 'Unknown' -Summary 'O WMI não retornou módulos de memória.' -Detail 'Verifique se o WMI está saudável.'
        }

        $slow = New-Object 'System.Collections.Generic.List[string]'
        $details = New-Object 'System.Collections.Generic.List[string]'

        foreach ($module in $modules) {
            $rated = [int]$module.Speed
            $configured = [int]$module.ConfiguredClockSpeed
            $slot = if ($module.DeviceLocator) { [string]$module.DeviceLocator } else { 'Slot desconhecido' }
            $sizeGb = if ($module.Capacity) { [math]::Round(([double]$module.Capacity / 1GB), 0) } else { 0 }

            if ($rated -gt 0 -and $configured -gt 0) {
                [void]$details.Add(("{0}: {1} GB @ {2} MT/s (nominal {3})" -f $slot, $sizeGb, $configured, $rated))
                if ($configured -lt ($rated - 100)) {
                    [void]$slow.Add(("{0}: {1} MT/s de {2} MT/s" -f $slot, $configured, $rated))
                }
            }
        }

        if ($slow.Count -gt 0) {
            return New-OptiKitDiagnosticItem -Id 'RamXmp' -Title 'Memória RAM (XMP/EXPO)' -Status 'Warn' -Summary ("{0} módulo(s) abaixo da velocidade nominal." -f $slow.Count) -Detail (($slow -join '; ') + '. Ative XMP/EXPO na BIOS se a placa-mãe e a CPU suportarem.') -ActionText 'Verificar XMP/EXPO na BIOS'
        }
        if ($details.Count -eq 0) {
            return New-OptiKitDiagnosticItem -Id 'RamXmp' -Title 'Memória RAM (XMP/EXPO)' -Status 'Unknown' -Summary 'Velocidade de RAM não reportada pelo WMI.' -Detail 'ConfiguredClockSpeed/Speed retornaram 0.'
        }
        return New-OptiKitDiagnosticItem -Id 'RamXmp' -Title 'Memória RAM (XMP/EXPO)' -Status 'OK' -Summary 'Módulos operando na velocidade nominal.' -Detail ($details -join '; ')
    }
    catch {
        return New-OptiKitDiagnosticItem -Id 'RamXmp' -Title 'Memória RAM (XMP/EXPO)' -Status 'Unknown' -Summary 'Falha ao consultar a memória.' -Detail $_.Exception.Message
    }
}

function Get-OptiKitDisplayModes {
    [CmdletBinding()]
    param()

    if (-not ('OptiKit.DisplayModes' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace OptiKit {
    public static class DisplayModes {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
        public struct DEVMODE {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public short dmSpecVersion;
            public short dmDriverVersion;
            public short dmSize;
            public short dmDriverExtra;
            public int dmFields;
            public int dmPositionX;
            public int dmPositionY;
            public int dmDisplayOrientation;
            public int dmDisplayFixedOutput;
            public short dmColor;
            public short dmDuplex;
            public short dmYResolution;
            public short dmTTOption;
            public short dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public short dmLogPixels;
            public int dmBitsPerPel;
            public int dmPelsWidth;
            public int dmPelsHeight;
            public int dmDisplayFlags;
            public int dmDisplayFrequency;
            public int dmICMMethod;
            public int dmICMIntent;
            public int dmMediaType;
            public int dmDitherType;
            public int dmReserved1;
            public int dmReserved2;
            public int dmPanningWidth;
            public int dmPanningHeight;
        }

        [DllImport("user32.dll", CharSet = CharSet.Ansi)]
        public static extern bool EnumDisplaySettings(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode);

        public static int Size { get { return Marshal.SizeOf(typeof(DEVMODE)); } }
    }
}
'@
    }

    $results = New-Object 'System.Collections.Generic.List[pscustomobject]'
    for ($displayIndex = 1; $displayIndex -le 8; $displayIndex++) {
        $deviceName = "\\.\DISPLAY$displayIndex"
        $current = New-Object 'OptiKit.DisplayModes+DEVMODE'
        $current.dmSize = [int16][OptiKit.DisplayModes]::Size
        if (-not [OptiKit.DisplayModes]::EnumDisplaySettings($deviceName, -1, [ref]$current)) {
            continue
        }

        $maxRefresh = 0
        $modeIndex = 0
        while ($true) {
            $mode = New-Object 'OptiKit.DisplayModes+DEVMODE'
            $mode.dmSize = [int16][OptiKit.DisplayModes]::Size
            if (-not [OptiKit.DisplayModes]::EnumDisplaySettings($deviceName, $modeIndex, [ref]$mode)) {
                break
            }
            if ($mode.dmPelsWidth -eq $current.dmPelsWidth -and $mode.dmPelsHeight -eq $current.dmPelsHeight -and $mode.dmDisplayFrequency -gt $maxRefresh) {
                $maxRefresh = [int]$mode.dmDisplayFrequency
            }
            $modeIndex++
        }

        [void]$results.Add([pscustomobject]@{
            DeviceName = $deviceName
            Width      = [int]$current.dmPelsWidth
            Height     = [int]$current.dmPelsHeight
            CurrentHz  = [int]$current.dmDisplayFrequency
            MaxHz      = $maxRefresh
        })
    }

    return $results.ToArray()
}

function Get-OptiKitDiagnosticMonitor {
    [CmdletBinding()]
    param()

    try {
        $modes = @(Get-OptiKitDisplayModes)
        if ($modes.Count -eq 0) {
            return New-OptiKitDiagnosticItem -Id 'MonitorRefresh' -Title 'Taxa de Atualização do Monitor' -Status 'Unknown' -Summary 'Não foi possível enumerar os modos de vídeo.' -Detail 'EnumDisplaySettings não retornou displays ativos.'
        }

        $warnings = New-Object 'System.Collections.Generic.List[string]'
        $details = New-Object 'System.Collections.Generic.List[string]'

        foreach ($mode in $modes) {
            [void]$details.Add(("{0}: {1}x{2} @ {3} Hz (máx. {4} Hz)" -f $mode.DeviceName, $mode.Width, $mode.Height, $mode.CurrentHz, $mode.MaxHz))
            if ($mode.MaxHz -gt 0 -and $mode.CurrentHz -gt 0 -and $mode.CurrentHz -lt ($mode.MaxHz - 1)) {
                [void]$warnings.Add(("{0}: {1} Hz de {2} Hz em {3}x{4}" -f $mode.DeviceName, $mode.CurrentHz, $mode.MaxHz, $mode.Width, $mode.Height))
            }
        }

        if ($warnings.Count -gt 0) {
            return New-OptiKitDiagnosticItem -Id 'MonitorRefresh' -Title 'Taxa de Atualização do Monitor' -Status 'Warn' -Summary ("{0} monitor(es) abaixo da taxa máxima." -f $warnings.Count) -Detail (($warnings -join '; ') + '. Ajuste em Configurações > Sistema > Vídeo > Taxa de atualização.') -ActionText 'Abrir configurações de vídeo do Windows'
        }
        return New-OptiKitDiagnosticItem -Id 'MonitorRefresh' -Title 'Taxa de Atualização do Monitor' -Status 'OK' -Summary 'Monitores na taxa máxima disponível para a resolução atual.' -Detail ($details -join '; ')
    }
    catch {
        return New-OptiKitDiagnosticItem -Id 'MonitorRefresh' -Title 'Taxa de Atualização do Monitor' -Status 'Unknown' -Summary 'Falha ao consultar os modos de vídeo.' -Detail $_.Exception.Message
    }
}

function Get-OptiKitDiagnosticDeviceGuard {
    [CmdletBinding()]
    param()

    try {
        $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName 'Win32_DeviceGuard' -ErrorAction Stop
        $vbsStatus = [int]$dg.VirtualizationBasedSecurityStatus
        $services = @($dg.SecurityServicesRunning)
        $hvci = $services -contains 2
        $summary = if ($hvci) { 'VBS/HVCI ativo' } elseif ($vbsStatus -eq 2) { 'VBS ativo, HVCI desligado' } else { 'VBS/HVCI desligado' }
        $detail = "VirtualizationBasedSecurityStatus=$vbsStatus; SecurityServicesRunning=$($services -join ',')."

        if ($hvci) {
            return New-OptiKitDiagnosticItem -Id 'DeviceGuard' -Title 'VBS / Integridade da Memória (HVCI)' -Status 'Warn' -Summary $summary -Detail ($detail + ' HVCI custa de 3% a 7% em jogos CPU-bound, mas pode ser exigido por anti-cheats. Só desative se nenhum anti-cheat exigir.') -ActionText 'Ver tweak Avançado HVCI'
        }
        return New-OptiKitDiagnosticItem -Id 'DeviceGuard' -Title 'VBS / Integridade da Memória (HVCI)' -Status 'OK' -Summary $summary -Detail $detail
    }
    catch {
        return New-OptiKitDiagnosticItem -Id 'DeviceGuard' -Title 'VBS / Integridade da Memória (HVCI)' -Status 'Unknown' -Summary 'Falha ao consultar o DeviceGuard.' -Detail $_.Exception.Message
    }
}

function Get-OptiKitEnergySaverState {
    [CmdletBinding()]
    param()

    if (-not ('OptiKit.PowerStatus' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace OptiKit {
    public static class PowerStatus {
        [StructLayout(LayoutKind.Sequential)]
        public struct SYSTEM_POWER_STATUS {
            public byte ACLineStatus;
            public byte BatteryFlag;
            public byte BatteryLifePercent;
            public byte SystemStatusFlag;
            public uint BatteryLifeTime;
            public uint BatteryFullLifeTime;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS status);
    }
}
'@
    }

    $status = New-Object 'OptiKit.PowerStatus+SYSTEM_POWER_STATUS'
    if (-not [OptiKit.PowerStatus]::GetSystemPowerStatus([ref]$status)) {
        return $null
    }
    return (($status.SystemStatusFlag -band 1) -ne 0)
}

function Get-OptiKitDiagnosticGamingToggles {
    [CmdletBinding()]
    param()

    try {
        $hagsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
        $hags = Get-RegistryEntryState -Path $hagsKey -Name 'HwSchMode' -FallbackType 'DWord'
        $hagsOn = ($hags.ValueExisted -and [int]$hags.Value -eq 2)

        $gameBarKey = 'HKCU:\Software\Microsoft\GameBar'
        $autoGameMode = Get-RegistryEntryState -Path $gameBarKey -Name 'AutoGameModeEnabled' -FallbackType 'DWord'
        $allowGameMode = Get-RegistryEntryState -Path $gameBarKey -Name 'AllowAutoGameMode' -FallbackType 'DWord'
        $gameModeOn = ($autoGameMode.ValueExisted -and [int]$autoGameMode.Value -eq 1 -and $allowGameMode.ValueExisted -and [int]$allowGameMode.Value -eq 1)

        $planGuid = Get-ActivePowerPlanGuid
        $balancedGuid = '381b4222-f694-41f0-9685-ff5bb260df2e'
        $highGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        $hardware = Get-OptiKitHardware
        $planName = if ($planGuid -eq $balancedGuid) { 'Equilibrado' } elseif ($planGuid -eq $highGuid) { 'Alto Desempenho' } else { 'Outro/Ultimate' }
        $planOk = if ($hardware.IsX3D -or $hardware.IsLaptop) { $planGuid -eq $balancedGuid } else { $planGuid -ne $balancedGuid }
        $planNote = if ($hardware.IsX3D -or $hardware.IsLaptop) { 'Equilibrado é o esperado para X3D/notebook.' } else { 'Alto Desempenho é o esperado para desktop.' }

        $warnings = New-Object 'System.Collections.Generic.List[string]'
        if (-not $hagsOn) { [void]$warnings.Add('HAGS desativado') }
        if (-not $gameModeOn) { [void]$warnings.Add('Game Mode desativado') }
        if (-not $planOk) { [void]$warnings.Add(("Plano de energia: {0}" -f $planName)) }
        $vramNote = ''
        if ($hagsOn -and (Test-OptiKitHagsVramConstrained -Hardware $hardware)) {
            $vramNote = (" HAGS ativo com VRAM limitada ({0} GB): teste desativar se faltar VRAM. Frame Generation exige HAGS." -f $hardware.GpuVramGB)
            [void]$warnings.Add(("HAGS com VRAM limitada ({0} GB)" -f $hardware.GpuVramGB))
        }

        $detail = ("HAGS={0}; Game Mode={1}; Plano={2}. {3}{4}" -f $(if ($hagsOn) { 'on' } else { 'off' }), $(if ($gameModeOn) { 'on' } else { 'off' }), $planName, $planNote, $vramNote)
        if ($warnings.Count -gt 0) {
            return New-OptiKitDiagnosticItem -Id 'GamingToggles' -Title 'HAGS, Game Mode e Plano de Energia' -Status 'Warn' -Summary ($warnings -join '; ') -Detail $detail -ActionText 'Aplicar tweaks de Desempenho & Energia'
        }
        return New-OptiKitDiagnosticItem -Id 'GamingToggles' -Title 'HAGS, Game Mode e Plano de Energia' -Status 'OK' -Summary 'Configurações de gaming ativas.' -Detail $detail
    }
    catch {
        return New-OptiKitDiagnosticItem -Id 'GamingToggles' -Title 'HAGS, Game Mode e Plano de Energia' -Status 'Unknown' -Summary 'Falha ao consultar as configurações de gaming.' -Detail $_.Exception.Message
    }
}

function Get-OptiKitDiagnosticWindowsGamingState {
    [CmdletBinding()]
    param()

    try {
        $windowed = Test-OptiKitWindowedGameOptimizations
        $energy = Get-OptiKitEnergySaverState
        $warnings = New-Object 'System.Collections.Generic.List[string]'
        $details = New-Object 'System.Collections.Generic.List[string]'

        if (-not $windowed) {
            [void]$warnings.Add('Otimizações para jogos em janela desativadas')
            [void]$details.Add('Otimizações de janela=off')
        }
        else {
            [void]$details.Add('Otimizações de janela=on')
        }

        if ($energy -eq $true) {
            [void]$warnings.Add('Economia de energia/battery saver ativo')
            [void]$details.Add('Economia de energia=on')
        }
        elseif ($energy -eq $false) {
            [void]$details.Add('Economia de energia=off')
        }
        else {
            [void]$details.Add('Economia de energia=desconhecida')
        }

        if ($warnings.Count -gt 0) {
            return New-OptiKitDiagnosticItem -Id 'WindowsGamingState' -Title 'Otimizações de jogos e energia' -Status 'Warn' -Summary ($warnings -join '; ') -Detail (($details -join '; ') + '.') -ActionText 'Revisar configurações de vídeo e energia'
        }
        return New-OptiKitDiagnosticItem -Id 'WindowsGamingState' -Title 'Otimizações de jogos e energia' -Status 'OK' -Summary 'Otimizações de janela e energia sem alertas.' -Detail (($details -join '; ') + '.')
    }
    catch {
        return New-OptiKitDiagnosticItem -Id 'WindowsGamingState' -Title 'Otimizações de jogos e energia' -Status 'Unknown' -Summary 'Falha ao consultar otimizações de jogos e energia.' -Detail $_.Exception.Message
    }
}

function Get-OptiKitDiagnosticX3dService {
    [CmdletBinding()]
    param()

    try {
        $hardware = Get-OptiKitHardware
        if (-not $hardware.IsX3D) {
            return New-OptiKitDiagnosticItem -Id 'X3dService' -Title 'Driver 3D V-Cache (AMD)' -Status 'Info' -Summary 'CPU sem 3D V-Cache; verificação não aplicável.' -Detail 'Nenhuma ação necessária.'
        }
        if (-not $hardware.IsX3DDualCcd) {
            return New-OptiKitDiagnosticItem -Id 'X3dService' -Title 'Driver 3D V-Cache (AMD)' -Status 'OK' -Summary 'X3D single-CCD; core parking entre CCDs não é necessário.' -Detail ("CPU: {0}" -f $hardware.CpuName)
        }

        $service = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)amd3dvcache' } | Select-Object -First 1
        $driver = Get-CimInstance -ClassName Win32_SystemDriver -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)amd3dvcache' } | Select-Object -First 1
        $chipsetUrl = 'https://www.amd.com/en/support/download/drivers.html'

        if (-not $service -and -not $driver) {
            return New-OptiKitDiagnosticItem -Id 'X3dService' -Title 'Driver 3D V-Cache (AMD)' -Status 'Error' -Summary 'CPU X3D dual-CCD sem o serviço amd3dvcache.' -Detail 'O core parking do 3D V-Cache não funciona sem o driver de chipset AMD. Instale o chipset mais recente.' -ActionText 'Baixar driver de chipset AMD' -ActionUrl $chipsetUrl
        }

        $serviceState = if ($service) { $service.Status.ToString() } else { 'driver presente' }
        if ($service -and $service.Status -ne 'Running') {
            return New-OptiKitDiagnosticItem -Id 'X3dService' -Title 'Driver 3D V-Cache (AMD)' -Status 'Warn' -Summary ("Serviço amd3dvcache presente, mas {0}." -f $serviceState) -Detail 'Reinicie o PC ou reinstale o driver de chipset AMD.' -ActionText 'Baixar driver de chipset AMD' -ActionUrl $chipsetUrl
        }
        return New-OptiKitDiagnosticItem -Id 'X3dService' -Title 'Driver 3D V-Cache (AMD)' -Status 'OK' -Summary 'Serviço amd3dvcache presente.' -Detail ("CPU: {0}; Estado: {1}" -f $hardware.CpuName, $serviceState)
    }
    catch {
        return New-OptiKitDiagnosticItem -Id 'X3dService' -Title 'Driver 3D V-Cache (AMD)' -Status 'Unknown' -Summary 'Falha ao consultar o driver AMD 3D V-Cache.' -Detail $_.Exception.Message
    }
}

function Get-OptiKitDiagnosticGpuDriver {
    [CmdletBinding()]
    param()

    try {
        $gpus = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop | Where-Object { $_.Name -and $_.Name -notmatch '(?i)Microsoft Basic Display|Remote Display' })
        if ($gpus.Count -eq 0) {
            return New-OptiKitDiagnosticItem -Id 'GpuDriver' -Title 'Idade do Driver de GPU' -Status 'Unknown' -Summary 'Nenhuma GPU discreta/integrada reportada.' -Detail 'O WMI não retornou Win32_VideoController.'
        }

        $warnings = New-Object 'System.Collections.Generic.List[string]'
        $details = New-Object 'System.Collections.Generic.List[string]'
        $actionText = $null
        $actionUrl = $null

        foreach ($gpu in $gpus) {
            $driverDate = $null
            try {
                $driverDate = [datetime]$gpu.DriverDate
            }
            catch {
                Write-Verbose ("DriverDate inválida para {0}" -f $gpu.Name)
            }
            if (-not $driverDate) {
                continue
            }

            $ageDays = [int]((Get-Date) - $driverDate).TotalDays
            [void]$details.Add(("{0}: driver {1:yyyy-MM-dd} ({2} dias)" -f $gpu.Name, $driverDate, $ageDays))
            if ($ageDays -gt 180) {
                [void]$warnings.Add(("{0}: {1} dias" -f $gpu.Name, $ageDays))
                if (-not $actionUrl) {
                    if ($gpu.Name -match '(?i)NVIDIA') {
                        $actionUrl = 'https://www.nvidia.com/Download/index.aspx'
                    }
                    elseif ($gpu.Name -match '(?i)AMD|Radeon') {
                        $actionUrl = 'https://www.amd.com/en/support/download/drivers.html'
                    }
                    elseif ($gpu.Name -match '(?i)Intel') {
                        $actionUrl = 'https://www.intel.com/content/www/us/en/download-center/home.html'
                    }
                    if ($actionUrl) { $actionText = 'Atualizar driver de vídeo' }
                }
            }
        }

        if ($warnings.Count -gt 0) {
            return New-OptiKitDiagnosticItem -Id 'GpuDriver' -Title 'Idade do Driver de GPU' -Status 'Warn' -Summary ("{0} driver(s) com mais de 180 dias." -f $warnings.Count) -Detail ($details -join '; ') -ActionText $actionText -ActionUrl $actionUrl
        }
        if ($details.Count -eq 0) {
            return New-OptiKitDiagnosticItem -Id 'GpuDriver' -Title 'Idade do Driver de GPU' -Status 'Unknown' -Summary 'Data do driver não reportada.' -Detail 'Win32_VideoController.DriverDate está vazio.'
        }
        return New-OptiKitDiagnosticItem -Id 'GpuDriver' -Title 'Idade do Driver de GPU' -Status 'OK' -Summary 'Drivers de GPU recentes.' -Detail ($details -join '; ')
    }
    catch {
        return New-OptiKitDiagnosticItem -Id 'GpuDriver' -Title 'Idade do Driver de GPU' -Status 'Unknown' -Summary 'Falha ao consultar o driver de GPU.' -Detail $_.Exception.Message
    }
}

function Format-OptiKitDiagnosticSize {
    param([double]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N1} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N0} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} KB' -f ($Bytes / 1KB))
}

function Get-OptiKitDiagnosticBios {
    [CmdletBinding()]
    param()

    try {
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop

        $manufacturer = [string]$computer.Manufacturer
        $model = [string]$computer.Model
        $version = [string]$bios.SMBIOSBIOSVersion
        $releaseDate = $null
        try { $releaseDate = [datetime]$bios.ReleaseDate } catch { $releaseDate = $null }

        $secureBoot = $null
        if (Get-Command Confirm-SecureBootUEFI -ErrorAction SilentlyContinue) {
            try { $secureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction Stop) } catch { $secureBoot = $null }
        }

        $tpm = $null
        if (Get-Command Get-Tpm -ErrorAction SilentlyContinue) {
            try { $tpm = Get-Tpm -ErrorAction Stop } catch { $tpm = $null }
        }

        $secureBootText = if ($null -eq $secureBoot) { 'Secure Boot indisponível' } elseif ($secureBoot) { 'Secure Boot ativo' } else { 'Secure Boot desativado' }
        $tpmText = 'TPM indisponível'
        $tpmOk = $false
        if ($tpm) {
            $tpmVersion = if ($tpm.SpecVersion) { [string]$tpm.SpecVersion } elseif ($tpm.TpmVersion) { [string]$tpm.TpmVersion } else { 'versão desconhecida' }
            $tpmPresent = [bool]$tpm.TpmPresent
            $tpmReady = [bool]$tpm.TpmReady
            $tpmOk = ($tpmPresent -and $tpmReady)
            $tpmText = if (-not $tpmPresent) { 'TPM ausente' } elseif (-not $tpmReady) { ("TPM {0} presente, não pronto" -f $tpmVersion) } else { ("TPM {0} pronto" -f $tpmVersion) }
        }

        $summaryParts = @($secureBootText, $tpmText)
        $summary = $summaryParts -join ' · '
        $detailParts = @()
        if ($manufacturer -or $model) { $detailParts += ("{0} {1}" -f $manufacturer, $model).Trim() }
        if ($version) {
            $dateText = if ($releaseDate) { $releaseDate.ToString('yyyy-MM-dd') } else { 'data desconhecida' }
            $detailParts += ("BIOS {0} ({1})" -f $version, $dateText)
        }
        $detailParts += 'Secure Boot, TPM, XMP/EXPO, fan curve e tensões são ajustados na BIOS/UEFI.'
        $detail = $detailParts -join '. '

        if ($null -eq $secureBoot) {
            return New-OptiKitDiagnosticItem -Id 'BiosFirmware' -Title 'BIOS / Firmware e Segurança' -Status 'Info' -Summary 'Leitura parcial: Secure Boot/TPM exigem UEFI e execução como Administrador.' -Detail $detail -ActionText 'Abra o OptiKit como Administrador para ler Secure Boot e TPM.'
        }
        if (-not $secureBoot -or ($tpm -and -not $tpmOk)) {
            return New-OptiKitDiagnosticItem -Id 'BiosFirmware' -Title 'BIOS / Firmware e Segurança' -Status 'Warn' -Summary $summary -Detail $detail -ActionText 'Use Manutenção > Reiniciar para a BIOS (UEFI) para ajustar Secure Boot, TPM e XMP/EXPO.'
        }
        if ($null -eq $tpm) {
            return New-OptiKitDiagnosticItem -Id 'BiosFirmware' -Title 'BIOS / Firmware e Segurança' -Status 'Info' -Summary $summary -Detail $detail -ActionText 'Leitura parcial: TPM indisponível; verifique no firmware.'
        }
        return New-OptiKitDiagnosticItem -Id 'BiosFirmware' -Title 'BIOS / Firmware e Segurança' -Status 'OK' -Summary $summary -Detail $detail
    }
    catch {
        return New-OptiKitDiagnosticItem -Id 'BiosFirmware' -Title 'BIOS / Firmware e Segurança' -Status 'Unknown' -Summary 'Falha ao consultar BIOS/firmware.' -Detail $_.Exception.Message
    }
}

function Get-OptiKitDiagnosticDisk {
    [CmdletBinding()]
    param(
        [object[]]$Disks,
        [hashtable]$ReliabilityCounters,
        [object]$SystemVolume
    )

    if ($null -eq $Disks) {
        if (-not (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue)) {
            return New-OptiKitDiagnosticItem -Id 'DiskHealth' -Title 'Saúde do Armazenamento' -Status 'Unknown' -Summary 'Cmdlets de armazenamento indisponíveis.' -Detail 'Get-PhysicalDisk não está disponível nesta edição do Windows.'
        }
        try {
            $Disks = @(Get-PhysicalDisk -ErrorAction Stop)
        }
        catch {
            return New-OptiKitDiagnosticItem -Id 'DiskHealth' -Title 'Saúde do Armazenamento' -Status 'Unknown' -Summary 'Falha ao consultar os discos.' -Detail $_.Exception.Message
        }
    }
    else {
        $Disks = @($Disks)
    }

    try {
        if ($Disks.Count -eq 0) {
            return New-OptiKitDiagnosticItem -Id 'DiskHealth' -Title 'Saúde do Armazenamento' -Status 'Unknown' -Summary 'Nenhum disco físico reportado.' -Detail 'Get-PhysicalDisk retornou vazio.'
        }

        $details = New-Object 'System.Collections.Generic.List[string]'
        $warnings = New-Object 'System.Collections.Generic.List[string]'
        $errors = New-Object 'System.Collections.Generic.List[string]'

        foreach ($disk in $Disks) {
            $health = [string]$disk.HealthStatus
            $media = [string]$disk.MediaType
            $size = [double]$disk.Size
            $wear = $null
            $deviceId = [string]$disk.DeviceId
            try {
                if ($ReliabilityCounters -and $ReliabilityCounters.ContainsKey($deviceId)) {
                    $counter = [pscustomobject]$ReliabilityCounters[$deviceId]
                }
                else {
                    $counter = Get-StorageReliabilityCounter -DeviceNumber ([int]$disk.DeviceId) -ErrorAction Stop
                }
                if ($null -ne $counter.Wear) { $wear = [int]$counter.Wear }
            }
            catch {
                Write-Verbose ("Reliability counter indisponível para {0}: {1}" -f $disk.FriendlyName, $_.Exception.Message)
            }

            $wearText = if ($null -ne $wear) { ", desgaste {0}%" -f $wear } else { '' }
            [void]$details.Add(("{0} ({1}, {2}{3})" -f $disk.FriendlyName, $media, (Format-OptiKitDiagnosticSize -Bytes $size), $wearText))

            if ($health -eq 'Unhealthy') {
                [void]$errors.Add(("{0}: saúde {1}" -f $disk.FriendlyName, $health))
            }
            elseif ($health -eq 'Warning') {
                [void]$warnings.Add(("{0}: saúde {1}" -f $disk.FriendlyName, $health))
            }
            if ($null -ne $wear -and $wear -ge 80) {
                [void]$warnings.Add(("{0}: desgaste {1}%" -f $disk.FriendlyName, $wear))
            }
        }

        try {
            $volume = $SystemVolume
            if (-not $volume) {
                $systemLetter = ($env:SystemDrive -replace ':', '')
                $volume = Get-Volume -DriveLetter $systemLetter -ErrorAction Stop
            }
            if ($volume -and $volume.Size -gt 0) {
                $freePct = [math]::Round(([double]$volume.SizeRemaining / [double]$volume.Size) * 100, 1)
                $freeText = "{0} livres de {1} ({2}%)" -f (Format-OptiKitDiagnosticSize -Bytes $volume.SizeRemaining), (Format-OptiKitDiagnosticSize -Bytes $volume.Size), $freePct
                [void]$details.Add(("Unidade {0}: {1}" -f $env:SystemDrive, $freeText))
                if ($freePct -lt 10) {
                    [void]$warnings.Add(("Unidade {0}: apenas {1}% livres" -f $env:SystemDrive, $freePct))
                }
            }
        }
        catch {
            Write-Verbose ("Falha ao consultar volume do sistema: {0}" -f $_.Exception.Message)
        }

        $detail = $details -join '; '
        if ($errors.Count -gt 0) {
            return New-OptiKitDiagnosticItem -Id 'DiskHealth' -Title 'Saúde do Armazenamento' -Status 'Error' -Summary ($errors -join '; ') -Detail $detail -ActionText 'Faça backup dos dados e verifique a saúde do disco com o fabricante.'
        }
        if ($warnings.Count -gt 0) {
            return New-OptiKitDiagnosticItem -Id 'DiskHealth' -Title 'Saúde do Armazenamento' -Status 'Warn' -Summary ($warnings -join '; ') -Detail $detail -ActionText 'Libere espaço e monitore o desgaste do SSD.'
        }
        return New-OptiKitDiagnosticItem -Id 'DiskHealth' -Title 'Saúde do Armazenamento' -Status 'OK' -Summary 'Discos saudáveis e espaço livre suficiente.' -Detail $detail
    }
    catch {
        return New-OptiKitDiagnosticItem -Id 'DiskHealth' -Title 'Saúde do Armazenamento' -Status 'Unknown' -Summary 'Falha ao consultar os discos.' -Detail $_.Exception.Message
    }
}

function Get-OptiKitDiagnosticStability {
    [CmdletBinding()]
    param()

    try {
        $since = (Get-Date).AddDays(-7)
        $whea = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since } -ErrorAction SilentlyContinue)
        $kernelPower = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 41; StartTime = $since } -ErrorAction SilentlyContinue)

        $details = New-Object 'System.Collections.Generic.List[string]'
        [void]$details.Add(("WHEA: {0} evento(s)" -f $whea.Count))
        [void]$details.Add(("Kernel-Power 41: {0} evento(s)" -f $kernelPower.Count))
        if ($whea.Count -gt 0) {
            [void]$details.Add(("Último WHEA: {0:yyyy-MM-dd HH:mm}" -f $whea[0].TimeCreated))
        }
        if ($kernelPower.Count -gt 0) {
            [void]$details.Add(("Último Kernel-Power 41: {0:yyyy-MM-dd HH:mm}" -f $kernelPower[0].TimeCreated))
        }
        $detail = $details -join '; '

        if ($whea.Count -gt 0) {
            return New-OptiKitDiagnosticItem -Id 'Stability' -Title 'Estabilidade (WHEA / Kernel-Power)' -Status 'Error' -Summary ("{0} erro(s) de hardware WHEA nos últimos 7 dias." -f $whea.Count) -Detail $detail -ActionText 'Atualize BIOS/drivers e remova overclock/undervolt antes de investigar.'
        }
        if ($kernelPower.Count -gt 0) {
            return New-OptiKitDiagnosticItem -Id 'Stability' -Title 'Estabilidade (WHEA / Kernel-Power)' -Status 'Warn' -Summary ("{0} desligamento(s) inesperado(s) nos últimos 7 dias." -f $kernelPower.Count) -Detail $detail -ActionText 'Verifique fonte, temperatura e estabilidade de RAM/CPU.'
        }
        return New-OptiKitDiagnosticItem -Id 'Stability' -Title 'Estabilidade (WHEA / Kernel-Power)' -Status 'OK' -Summary 'Nenhum erro WHEA ou desligamento inesperado nos últimos 7 dias.' -Detail $detail
    }
    catch {
        return New-OptiKitDiagnosticItem -Id 'Stability' -Title 'Estabilidade (WHEA / Kernel-Power)' -Status 'Unknown' -Summary 'Falha ao consultar o log de eventos.' -Detail $_.Exception.Message
    }
}

function Test-OptiKitPendingReboot {
    [CmdletBinding()]
    param()

    $reasons = New-Object 'System.Collections.Generic.List[string]'
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        [void]$reasons.Add('Componentes do Windows')
    }
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        [void]$reasons.Add('Windows Update')
    }
    try {
        $sessionManager = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction Stop
        if ($sessionManager -and @($sessionManager.PendingFileRenameOperations).Count -gt 0) {
            [void]$reasons.Add('Renomeação de arquivos')
        }
    }
    catch {
        Write-Verbose 'Sem PendingFileRenameOperations.'
    }

    return [pscustomobject]@{
        Pending = ($reasons.Count -gt 0)
        Reasons = $reasons.ToArray()
    }
}

function Get-OptiKitDiagnosticPendingReboot {
    [CmdletBinding()]
    param()

    try {
        $state = Test-OptiKitPendingReboot
        if ($state.Pending) {
            return New-OptiKitDiagnosticItem -Id 'PendingReboot' -Title 'Reinicialização Pendente' -Status 'Warn' -Summary 'O Windows tem alterações pendentes que exigem reinício.' -Detail ($state.Reasons -join '; ') -ActionText 'Reinicie o computador para concluir as alterações.'
        }
        return New-OptiKitDiagnosticItem -Id 'PendingReboot' -Title 'Reinicialização Pendente' -Status 'OK' -Summary 'Nenhuma reinicialização pendente.' -Detail 'Nenhuma chave de reboot pendente encontrada.'
    }
    catch {
        return New-OptiKitDiagnosticItem -Id 'PendingReboot' -Title 'Reinicialização Pendente' -Status 'Unknown' -Summary 'Falha ao verificar reinicialização pendente.' -Detail $_.Exception.Message
    }
}

function Get-OptiKitDiagnosticDefender {
    [CmdletBinding()]
    param()

    if (-not (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
        return New-OptiKitDiagnosticItem -Id 'Defender' -Title 'Microsoft Defender' -Status 'Unknown' -Summary 'Módulo do Defender indisponível.' -Detail 'Get-MpComputerStatus não está disponível; pode haver antivírus de terceiros.'
    }

    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        $av = [bool]$mp.AntivirusEnabled
        $rtp = [bool]$mp.RealTimeProtectionEnabled
        $signatureAge = [int]$mp.AntivirusSignatureAge
        $detail = ("Antivírus={0}; Tempo real={1}; Assinaturas com {2} dia(s)." -f $(if ($av) { 'on' } else { 'off' }), $(if ($rtp) { 'on' } else { 'off' }), $signatureAge)

        if (-not $av -or -not $rtp -or $signatureAge -gt 7) {
            return New-OptiKitDiagnosticItem -Id 'Defender' -Title 'Microsoft Defender' -Status 'Warn' -Summary 'Proteção em tempo real desligada ou assinaturas desatualizadas.' -Detail $detail -ActionText 'Abra a Segurança do Windows e atualize/reative a proteção.'
        }
        return New-OptiKitDiagnosticItem -Id 'Defender' -Title 'Microsoft Defender' -Status 'OK' -Summary 'Proteção ativa e assinaturas atualizadas.' -Detail $detail
    }
    catch {
        return New-OptiKitDiagnosticItem -Id 'Defender' -Title 'Microsoft Defender' -Status 'Unknown' -Summary 'Falha ao consultar o Defender.' -Detail $_.Exception.Message
    }
}

function Get-OptiKitHardwareDiagnostics {
    [CmdletBinding()]
    param()

    $items = New-Object 'System.Collections.Generic.List[pscustomobject]'
    foreach ($check in @(
        'Get-OptiKitDiagnosticBios',
        'Get-OptiKitDiagnosticDisk',
        'Get-OptiKitDiagnosticStability',
        'Get-OptiKitDiagnosticPendingReboot',
        'Get-OptiKitDiagnosticDefender',
        'Get-OptiKitDiagnosticRam',
        'Get-OptiKitDiagnosticMonitor',
        'Get-OptiKitDiagnosticDeviceGuard',
        'Get-OptiKitDiagnosticGamingToggles',
        'Get-OptiKitDiagnosticWindowsGamingState',
        'Get-OptiKitDiagnosticX3dService',
        'Get-OptiKitDiagnosticGpuDriver'
    )) {
        try {
            $item = & $check
            if ($item) {
                [void]$items.Add($item)
            }
        }
        catch {
            [void]$items.Add((New-OptiKitDiagnosticItem -Id $check -Title $check -Status 'Unknown' -Summary 'Falha na verificação.' -Detail $_.Exception.Message))
        }
    }

    return $items.ToArray()
}
