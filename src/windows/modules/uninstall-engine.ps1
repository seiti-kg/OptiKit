# Desinstalador: inventario de programas Win32/Appx e execucao do comando oficial

function Test-OptiKitProtectedUninstallName {
    [CmdletBinding()]
    param([string]$Name)

    return ($Name -match '(?i)^(Microsoft Store|Windows Store|Settings|Calculadora|Calculator|Captura de Tela|Snipping Tool|Xbox|Microsoft\.WindowsStore|Microsoft\.StorePurchaseApp|Microsoft\.WindowsCalculator|Microsoft\.ScreenSketch|Microsoft\.Xbox.*|Microsoft\.GamingServices|Microsoft\.DesktopAppInstaller|Microsoft\.VCLibs.*|Microsoft\.UI\.Xaml.*|Microsoft\.WindowsAppRuntime.*|windows\.immersivecontrolpanel|Microsoft\.Windows\.Settings|ShellExperienceHost|StartMenuExperienceHost|SearchHost)$')
}

function ConvertFrom-OptiKitRegistryEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Entry,
        [string]$Key
    )

    $displayName = [string]$Entry.DisplayName
    if ([string]::IsNullOrWhiteSpace($displayName)) { return $null }
    if ([int]$Entry.SystemComponent -eq 1) { return $null }
    if (-not [string]::IsNullOrWhiteSpace([string]$Entry.ParentKeyName)) { return $null }
    if ([string]$Entry.ReleaseType -in @('Update', 'Hotfix', 'Security Update', 'Update Rollup')) { return $null }
    if ($displayName -match '(?i)^(KB\d+|Security Update|Update for\s|Hotfix)') { return $null }
    if (Test-OptiKitProtectedUninstallName -Name $displayName) { return $null }

    $estimatedMb = 0
    if ($Entry.EstimatedSize) {
        $estimatedMb = [math]::Round(([double]$Entry.EstimatedSize / 1024), 1)
    }

    return [pscustomobject]@{
        Id                  = if ($Key) { $Key } else { $displayName }
        DisplayName         = $displayName
        DisplayVersion      = [string]$Entry.DisplayVersion
        Publisher           = [string]$Entry.Publisher
        InstallLocation     = [string]$Entry.InstallLocation
        EstimatedSizeMB     = $estimatedMb
        UninstallString     = [string]$Entry.UninstallString
        QuietUninstallString = [string]$Entry.QuietUninstallString
        Source              = 'Registry'
    }
}

function ConvertFrom-OptiKitAppxPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Package
    )

    if ($Package.IsFramework) { return $null }
    if ([string]::IsNullOrWhiteSpace([string]$Package.Name)) { return $null }
    if ([string]$Package.SignatureKind -eq 'System') { return $null }
    if (Test-OptiKitProtectedUninstallName -Name ([string]$Package.Name)) { return $null }

    return [pscustomobject]@{
        Id                  = [string]$Package.PackageFullName
        DisplayName         = [string]$Package.Name
        DisplayVersion      = [string]$Package.Version
        Publisher           = [string]$Package.Publisher
        InstallLocation     = [string]$Package.InstallLocation
        EstimatedSizeMB     = 0
        UninstallString     = ''
        QuietUninstallString = ''
        Source              = 'Appx'
    }
}

function Get-OptiKitInstalledPrograms {
    [CmdletBinding()]
    param()

    $items = New-Object 'System.Collections.Generic.List[object]'
    $roots = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($root in $roots) {
        try {
            foreach ($entry in @(Get-ItemProperty -Path $root -ErrorAction SilentlyContinue)) {
                $item = ConvertFrom-OptiKitRegistryEntry -Entry $entry -Key $entry.PSChildName
                if ($item) { [void]$items.Add($item) }
            }
        }
        catch {
            Write-Verbose ("Falha ao ler a raiz de desinstalação {0}: {1}" -f $root, $_.Exception.Message)
        }
    }

    try {
        foreach ($package in @(Get-AppxPackage -ErrorAction SilentlyContinue)) {
            $item = ConvertFrom-OptiKitAppxPackage -Package $package
            if ($item) { [void]$items.Add($item) }
        }
    }
    catch {
        Write-Verbose ("Falha ao ler pacotes Appx: {0}" -f $_.Exception.Message)
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $deduped = New-Object 'System.Collections.Generic.List[object]'
    foreach ($item in $items) {
        $key = ('{0}|{1}|{2}' -f $item.DisplayName, $item.Publisher, $item.DisplayVersion).ToLowerInvariant()
        if ($seen.Add($key)) { [void]$deduped.Add($item) }
    }
    return @($deduped | Sort-Object -Property DisplayName)
}

function Get-OptiKitUninstallCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$Program
    )

    if ($Program.Source -eq 'Appx') {
        return [pscustomobject]@{ File = 'Remove-AppxPackage'; Arguments = @('-Package', $Program.Id) }
    }

    $command = if (-not [string]::IsNullOrWhiteSpace($Program.UninstallString)) {
        [string]$Program.UninstallString
    }
    else {
        [string]$Program.QuietUninstallString
    }
    if ([string]::IsNullOrWhiteSpace($command)) {
        throw ("Comando de desinstalação ausente para '{0}'." -f $Program.DisplayName)
    }

    if ($command -match '(?i)msiexec(?:\.exe)?.*(?:\/I|\/X)\s*(\{[0-9A-F-]{36}\})') {
        return [pscustomobject]@{ File = 'msiexec.exe'; Arguments = @('/x', $matches[1], '/qb', '/norestart') }
    }

    if ($command.TrimStart().StartsWith('"')) {
        if ($command -match '^"([^"]+)"\s*(.*)$') {
            return [pscustomobject]@{ File = $matches[1]; Arguments = @($matches[2]) }
        }
    }

    $parts = $command.Trim() -split '\s+', 2
    return [pscustomobject]@{ File = $parts[0]; Arguments = if ($parts.Count -gt 1) { @($parts[1]) } else { @() } }
}

function Uninstall-OptiKitProgram {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$Program
    )

    if ($Program.Source -eq 'Appx') {
        Remove-AppxPackage -Package $Program.Id -ErrorAction Stop
        return
    }

    $command = Get-OptiKitUninstallCommand -Program $Program
    $process = Start-Process -FilePath $command.File -ArgumentList $command.Arguments -Wait -PassThru -ErrorAction Stop
    $exitCode = [int]$process.ExitCode
    if ($exitCode -ne 0 -and $exitCode -ne 3010) {
        throw ("Desinstalação de '{0}' retornou código {1}." -f $Program.DisplayName, $exitCode)
    }
}
