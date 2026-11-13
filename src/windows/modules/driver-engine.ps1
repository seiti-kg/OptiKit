# Inventario de drivers, links oficiais e backup via pnputil

$script:OptiKitDriverLinks = @{
    NVIDIA = 'https://www.nvidia.com/Download/index.aspx'
    AMD    = 'https://www.amd.com/en/support/download/drivers.html'
    Intel  = 'https://www.intel.com/content/www/us/en/download-center/home.html'
}

function Get-OptiKitDriverVendorLink {
    [CmdletBinding()]
    param(
        [string]$Manufacturer,
        [string]$DeviceName
    )

    $text = ("{0} {1}" -f $Manufacturer, $DeviceName)
    if ($text -match '(?i)NVIDIA|GeForce|RTX|GTX') { return $script:OptiKitDriverLinks.NVIDIA }
    if ($text -match '(?i)AMD|Radeon|Ryzen') { return $script:OptiKitDriverLinks.AMD }
    if ($text -match '(?i)Intel|Arc|Iris|UHD') { return $script:OptiKitDriverLinks.Intel }
    return $null
}

function ConvertTo-OptiKitDriverUpdateRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Update,
        [object[]]$Drivers = @()
    )

    if ([int]$Update.Type -ne 2 -or [bool]$Update.IsHidden) { return $null }

    $hardware = [string]$Update.DriverHardwareID
    $matched = $null
    if (-not [string]::IsNullOrWhiteSpace($hardware)) {
        $normalizedHardware = $hardware -replace '(?i)^monitor\\', 'display\'
        $matched = @($Drivers | Where-Object {
            $deviceId = [string]$_.HardwareID
            if ([string]::IsNullOrWhiteSpace($deviceId)) { return $false }
            $devicePrefix = ((@($deviceId -split '\\') | Select-Object -First 2) -join '\')
            $hardware -eq $deviceId -or
            $hardware -like ('*' + $deviceId + '*') -or
            $deviceId -like ('*' + $hardware + '*') -or
            $normalizedHardware -eq $devicePrefix
        }) | Select-Object -First 1
    }

    $date = $null
    try {
        if ($Update.DriverVerDate) { $date = [datetime]$Update.DriverVerDate }
    }
    catch {
        $date = $null
    }

    $sizeBytes = 0.0
    try {
        if ($Update.MaxDownloadSize) { $sizeBytes = [double]$Update.MaxDownloadSize }
    }
    catch {
        $sizeBytes = 0.0
    }
    $sizeMB = [math]::Round(($sizeBytes / 1MB), 1)
    $sizeText = if ($sizeBytes -ge 1MB) {
        ('{0:N1} MB' -f ($sizeBytes / 1MB))
    }
    elseif ($sizeBytes -gt 0) {
        ('{0:N0} KB' -f ($sizeBytes / 1KB))
    }
    else {
        '—'
    }

    $updateId = ''
    try {
        if ($Update.Identity) { $updateId = [string]$Update.Identity.UpdateID }
    }
    catch {
        $updateId = ''
    }

    $currentVersion = if ($matched -and -not [string]::IsNullOrWhiteSpace([string]$matched.DriverVersion)) { [string]$matched.DriverVersion } else { '—' }
    $availableVersion = if (-not [string]::IsNullOrWhiteSpace([string]$Update.DriverVerVersion)) { [string]$Update.DriverVerVersion } else { '—' }

    [pscustomobject]@{
        DeviceName       = if ($matched) { [string]$matched.DeviceName } else { [string]$Update.Title }
        CurrentVersion   = $currentVersion
        AvailableVersion = $availableVersion
        Provider         = [string]$Update.DriverProvider
        Date             = $date
        SizeMB           = $sizeMB
        SizeText         = $sizeText
        RebootRequired   = [bool]$Update.RebootRequired
        IsOptional       = [bool]$Update.BrowseOnly
        RebootText       = if ([bool]$Update.RebootRequired) { 'Sim' } else { 'Não' }
        OptionalText     = if ([bool]$Update.BrowseOnly) { 'Sim' } else { 'Não' }
        Title            = [string]$Update.Title
        Description      = [string]$Update.Description
        UpdateId         = $updateId
    }
}

function Get-OptiKitDriverUpdates {
    [CmdletBinding()]
    param(
        [object[]]$Drivers = @()
    )

    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $result = $searcher.Search('IsInstalled=0')
        $rows = New-Object 'System.Collections.Generic.List[object]'
        for ($i = 0; $i -lt $result.Updates.Count; $i++) {
            $update = $result.Updates.Item($i)
            if ([int]$update.Type -ne 2 -or [bool]$update.IsHidden) { continue }
            $row = ConvertTo-OptiKitDriverUpdateRow -Update $update -Drivers $Drivers
            if ($row) { [void]$rows.Add($row) }
        }
        return @($rows | Sort-Object -Property DeviceName, AvailableVersion)
    }
    catch {
        throw ("Falha ao consultar atualizações de drivers do Windows Update: {0}" -f $_.Exception.Message)
    }
}

function Get-OptiKitDriverInventory {
    [CmdletBinding()]
    param()

    try {
        $classes = @('Display', 'Net', 'Media', 'System', 'HDC', 'SCSIAdapter', 'USB', 'Bluetooth', 'HIDClass', 'Keyboard', 'Mouse', 'DiskDrive')
        $drivers = @(Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.DeviceName) -and
            ([string]$_.DeviceClass -in $classes)
        })

        $seen = New-Object 'System.Collections.Generic.HashSet[string]'
        $items = New-Object 'System.Collections.Generic.List[object]'
        foreach ($driver in $drivers) {
            $key = if (-not [string]::IsNullOrWhiteSpace([string]$driver.DeviceID)) { [string]$driver.DeviceID } else { ('{0}|{1}' -f $driver.DeviceName, $driver.DriverVersion) }
            if (-not $seen.Add($key)) { continue }

            $date = $null
            try {
                if ($driver.DriverDate) { $date = [datetime]$driver.DriverDate }
            }
            catch {
                $date = $null
            }

            [void]$items.Add([pscustomobject]@{
                DeviceName    = [string]$driver.DeviceName
                DeviceClass   = [string]$driver.DeviceClass
                DriverVersion = [string]$driver.DriverVersion
                DriverDate    = $date
                Manufacturer  = [string]$driver.Manufacturer
                HardwareID    = [string]$driver.DeviceID
                Status        = 'OK'
                Link          = Get-OptiKitDriverVendorLink -Manufacturer ([string]$driver.Manufacturer) -DeviceName ([string]$driver.DeviceName)
            })
        }

        $problems = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
            $null -ne $_.ConfigManagerErrorCode -and [int]$_.ConfigManagerErrorCode -ne 0
        })
        foreach ($problem in $problems) {
            $name = if ($problem.Name) { [string]$problem.Name } else { [string]$problem.DeviceID }
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            [void]$items.Add([pscustomobject]@{
                DeviceName    = $name
                DeviceClass   = [string]$problem.DeviceClass
                DriverVersion = ''
                DriverDate    = $null
                Manufacturer  = [string]$problem.Manufacturer
                HardwareID    = [string]$problem.DeviceID
                Status        = 'Problema'
                Link          = Get-OptiKitDriverVendorLink -Manufacturer ([string]$problem.Manufacturer) -DeviceName $name
            })
        }

        $unique = New-Object 'System.Collections.Generic.List[object]'
        $finalKeys = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($item in $items) {
            $key = ('{0}|{1}|{2}' -f $item.DeviceName, $item.DeviceClass, $item.DriverVersion).ToLowerInvariant()
            if ($finalKeys.Add($key)) { [void]$unique.Add($item) }
        }
        return @($unique | Sort-Object -Property DeviceClass, DeviceName)
    }
    catch {
        throw ("Falha ao ler drivers do sistema: {0}" -f $_.Exception.Message)
    }
}

function Export-OptiKitDrivers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -Path $Destination -ItemType Directory -Force | Out-Null
    }
    $pnputil = Join-Path $env:SystemRoot 'System32\pnputil.exe'
    $process = Start-Process -FilePath $pnputil -ArgumentList @('/export-driver', '*', ('"{0}"' -f $Destination)) -Wait -PassThru -ErrorAction Stop
    if ([int]$process.ExitCode -ne 0) {
        throw ("pnputil falhou ao exportar drivers (código {0})." -f $process.ExitCode)
    }
    return $Destination
}
