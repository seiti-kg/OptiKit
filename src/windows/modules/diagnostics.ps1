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

        $detail = ("HAGS={0}; Game Mode={1}; Plano={2}. {3}" -f $(if ($hagsOn) { 'on' } else { 'off' }), $(if ($gameModeOn) { 'on' } else { 'off' }), $planName, $planNote)
        if ($warnings.Count -gt 0) {
            return New-OptiKitDiagnosticItem -Id 'GamingToggles' -Title 'HAGS, Game Mode e Plano de Energia' -Status 'Warn' -Summary ($warnings -join '; ') -Detail $detail -ActionText 'Aplicar tweaks de Desempenho & Energia'
        }
        return New-OptiKitDiagnosticItem -Id 'GamingToggles' -Title 'HAGS, Game Mode e Plano de Energia' -Status 'OK' -Summary 'Configurações de gaming ativas.' -Detail $detail
    }
    catch {
        return New-OptiKitDiagnosticItem -Id 'GamingToggles' -Title 'HAGS, Game Mode e Plano de Energia' -Status 'Unknown' -Summary 'Falha ao consultar as configurações de gaming.' -Detail $_.Exception.Message
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

function Get-OptiKitHardwareDiagnostics {
    [CmdletBinding()]
    param()

    $items = New-Object 'System.Collections.Generic.List[pscustomobject]'
    foreach ($check in @(
        'Get-OptiKitDiagnosticRam',
        'Get-OptiKitDiagnosticMonitor',
        'Get-OptiKitDiagnosticDeviceGuard',
        'Get-OptiKitDiagnosticGamingToggles',
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
