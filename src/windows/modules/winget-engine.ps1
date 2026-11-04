# Motor Winget (verificação, bootstrap oficial com verificação Authenticode, instalação silenciosa) e gestão segura do OneDrive

#region dev-only
if (-not (Get-Command Write-OptimizerLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\core\logger.ps1')
}
#endregion

function Test-WingetAvailable {
    [CmdletBinding()]
    param()

    $wingetCmd = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    $wingetPath = if ($wingetCmd) { $wingetCmd.Source } else { Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe' }

    if (-not $wingetPath -or -not (Test-Path -LiteralPath $wingetPath)) {
        return [pscustomobject]@{
            Available = $false
            Path      = $null
            Version   = $null
            IsHealthy = $false
        }
    }

    try {
        $verRaw = (& $wingetPath --version 2>$null | Out-String).Trim()
        $cleanVer = $verRaw -replace '^v', '' -replace '-.*$', ''
        $parsedVer = $null
        $isHealthy = [version]::TryParse($cleanVer, [ref]$parsedVer) -and ($parsedVer -ge [version]'1.6.0')
        return [pscustomobject]@{
            Available = $true
            Path      = $wingetPath
            Version   = $verRaw
            IsHealthy = $isHealthy
        }
    }
    catch {
        return [pscustomobject]@{
            Available = $false
            Path      = $wingetPath
            Version   = $null
            IsHealthy = $false
        }
    }
}

function Install-WingetBootstrap {
    [CmdletBinding()]
    param()

    if ($script:OptiKit -and $script:OptiKit.DryRun) {
        Write-OptimizerLog -Level DRYRUN -Message 'Instalar/reparar Microsoft App Installer (Winget Bootstrap)'
        return $true
    }

    Write-OptimizerLog -Level INFO -Message 'Verificando disponibilidade e integridade do Winget...'
    if (Get-Command 'Repair-WinGetPackageManager' -ErrorAction SilentlyContinue) {
        try {
            Write-OptimizerLog -Level INFO -Message 'Tentando reparo via Repair-WinGetPackageManager...'
            Repair-WinGetPackageManager -AllUsers -ErrorAction Stop
            if ((Test-WingetAvailable).IsHealthy) {
                Write-OptimizerLog -Level OK -Message 'Winget reparado com sucesso via Microsoft.WinGet.Client.'
                return $true
            }
        }
        catch {
            Write-OptimizerLog -Level WARN -Message ("Repair-WinGetPackageManager falhou: {0}. Tentando pacote oficial do GitHub..." -f $_.Exception.Message)
        }
    }

    $tempDir = Join-Path $env:TEMP ("optikit_winget_" + [Guid]::NewGuid().ToString('N'))
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $vcLibsUrl = 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx'
        $vcLibsFile = Join-Path $tempDir 'Microsoft.VCLibs.x64.14.00.Desktop.appx'
        Write-OptimizerLog -Level INFO -Message 'Baixando dependência VCLibs Desktop...'
        Invoke-WebRequest -Uri $vcLibsUrl -OutFile $vcLibsFile -UseBasicParsing -ErrorAction Stop
        Add-AppxPackage -Path $vcLibsFile -ErrorAction SilentlyContinue

        $relApi = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
        $release = Invoke-RestMethod -Uri $relApi -UseBasicParsing -ErrorAction Stop
        $bundleAsset = $release.assets | Where-Object { $_.name -match '\.msixbundle$' } | Select-Object -First 1
        if (-not $bundleAsset) {
            throw 'Asset .msixbundle não encontrado na release oficial microsoft/winget-cli.'
        }

        $bundlePath = Join-Path $tempDir $bundleAsset.name
        Write-OptimizerLog -Level INFO -Message ("Baixando {0}..." -f $bundleAsset.name)
        Invoke-WebRequest -Uri $bundleAsset.browser_download_url -OutFile $bundlePath -UseBasicParsing -ErrorAction Stop

        $sig = Get-AuthenticodeSignature -FilePath $bundlePath
        if ($sig.Status -ne 'Valid') {
            throw ("Assinatura Authenticode inválida para {0} (Status: {1})" -f $bundlePath, $sig.Status)
        }

        Add-AppxPackage -Path $bundlePath -ErrorAction Stop
        $status = Test-WingetAvailable
        if ($status.Available) {
            Write-OptimizerLog -Level OK -Message ("Winget instalado com sucesso ({0})." -f $status.Version)
            return $true
        }
        return $false
    }
    catch {
        Write-OptimizerLog -Level ERROR -Message ("Falha no bootstrap do Winget: {0}" -f $_.Exception.Message)
        return $false
    }
    finally {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Install-OptiKitApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppKey,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$AppConfig
    )

    $wingetId = $AppConfig.winget
    $displayName = if ($AppConfig.name) { $AppConfig.name } else { $AppKey }

    if ([string]::IsNullOrWhiteSpace($wingetId)) {
        Write-OptimizerLog -Level WARN -Message ("Aplicativo '{0}' não possui ID do Winget mapeado." -f $displayName)
        return $false
    }

    if ($script:OptiKit -and $script:OptiKit.DryRun) {
        Write-OptimizerLog -Level DRYRUN -Message ("Instalar aplicativo via Winget: {0} ({1})" -f $displayName, $wingetId)
        return $true
    }

    $wg = Test-WingetAvailable
    if (-not $wg.Available) {
        Write-OptimizerLog -Level WARN -Message 'Winget não encontrado. Iniciando instalação automática do App Installer...'
        if (-not (Install-WingetBootstrap)) {
            Write-OptimizerLog -Level ERROR -Message ("Não foi possível instalar '{0}' porque o Winget está indisponível." -f $displayName)
            return $false
        }
        $wg = Test-WingetAvailable
    }

    Write-OptimizerLog -Level INFO -Message ("Instalando {0} ({1})..." -f $displayName, $wingetId)
    $wingetArgs = @(
        'install',
        '--id', $wingetId,
        '--exact',
        '--silent',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--disable-interactivity'
    )

    try {
        $proc = Start-Process -FilePath $wg.Path -ArgumentList $wingetArgs -NoNewWindow -Wait -PassThru
        $exitCode = $proc.ExitCode
        # -1978335189 (0x8A15002B) = No applicable upgrade / already installed
        if ($exitCode -eq 0) {
            Write-OptimizerLog -Level OK -Message ("{0} instalado com sucesso." -f $displayName)
            return $true
        }
        elseif ($exitCode -eq -1978335189) {
            Write-OptimizerLog -Level INFO -Message ("{0} já está instalado na versão mais recente." -f $displayName)
            return $true
        }
        elseif ($exitCode -eq 3010) {
            Write-OptimizerLog -Level OK -Message ("{0} instalado com sucesso (reinicialização recomendada)." -f $displayName)
            return $true
        }
        else {
            Write-OptimizerLog -Level WARN -Message ("Winget retornou código {0} ao instalar {1}." -f $exitCode, $displayName)
            return $false
        }
    }
    catch {
        Write-OptimizerLog -Level ERROR -Message ("Erro ao executar Winget para {0}: {1}" -f $displayName, $_.Exception.Message)
        return $false
    }
}

function Test-OneDriveKfmActive {
    [CmdletBinding()]
    param()

    $usfPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    if (-not (Test-Path -LiteralPath $usfPath)) {
        return $false
    }

    $props = Get-ItemProperty -LiteralPath $usfPath -ErrorAction SilentlyContinue
    if (-not $props) {
        return $false
    }

    foreach ($folderName in @('Desktop', 'Personal', 'My Pictures', '{374DE290-123F-4565-9164-39C4925E467B}')) {
        $val = $props.$folderName
        if ($val -and ($val -match '(?i)OneDrive')) {
            return $true
        }
    }
    return $false
}

function Remove-OptiKitOneDrive {
    [CmdletBinding()]
    param()

    if (Test-OneDriveKfmActive) {
        $msg = 'Remoção do OneDrive bloqueada por segurança: suas pastas Área de Trabalho/Documentos estão redirecionadas para o OneDrive (Known Folder Move). Desative o backup de pastas nas configurações do OneDrive antes de removê-lo.'
        Write-OptimizerLog -Level WARN -Message $msg
        throw $msg
    }

    Invoke-Mutation -Description 'Encerrar processo e desinstalar Microsoft OneDrive' -Action {
        Stop-Process -Name 'OneDrive' -Force -ErrorAction SilentlyContinue
        $setupPaths = @(
            (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'),
            (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDriveSetup.exe')
        )
        $setupExe = $setupPaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($setupExe) {
            Start-Process -FilePath $setupExe -ArgumentList '/uninstall' -NoNewWindow -Wait | Out-Null
        }
    } | Out-Null
}

function Install-OptiKitOneDrive {
    [CmdletBinding()]
    param()

    Invoke-Mutation -Description 'Reinstalar Microsoft OneDrive' -Action {
        $setupPaths = @(
            (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe'),
            (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe')
        )
        $setupExe = $setupPaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($setupExe) {
            Start-Process -FilePath $setupExe -NoNewWindow -Wait | Out-Null
        }
        else {
            $wg = Test-WingetAvailable
            if ($wg.Available) {
                Start-Process -FilePath $wg.Path -ArgumentList @('install', '--id', 'Microsoft.OneDrive', '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements') -NoNewWindow -Wait | Out-Null
            }
        }
    } | Out-Null
}

function Test-OptiKitOneDriveRemoved {
    [CmdletBinding()]
    param()

    $exeLocal = Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'
    $exeProg = Join-Path ${env:ProgramFiles} 'Microsoft OneDrive\OneDrive.exe'
    return (-not (Test-Path -LiteralPath $exeLocal)) -and (-not (Test-Path -LiteralPath $exeProg))
}

function Invoke-OptiKitWingetCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WingetPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $WingetPath -ArgumentList $Arguments -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        foreach ($line in @(Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue)) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                Write-OptimizerLog -Level INFO -Message ("[{0}] {1}" -f $Label, $line.Trim())
            }
        }
        foreach ($line in @(Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue)) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                Write-OptimizerLog -Level WARN -Message ("[{0}] {1}" -f $Label, $line.Trim())
            }
        }
        return [int]$proc.ExitCode
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-OptiKitWingetUpgrade {
    [CmdletBinding()]
    param(
        [switch]$All,
        [string[]]$Ids
    )

    $cleanIds = @($Ids | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if (-not $All -and $cleanIds.Count -eq 0) {
        throw 'Informe -All ou pelo menos um ID do Winget para atualizar.'
    }

    if ($script:OptiKit -and $script:OptiKit.DryRun) {
        Write-OptimizerLog -Level DRYRUN -Message ("Atualizar aplicativos via Winget ({0})" -f $(if ($All) { 'todos' } else { $cleanIds -join ', ' }))
        return $true
    }

    $wg = Test-WingetAvailable
    if (-not $wg.Available) {
        Write-OptimizerLog -Level WARN -Message 'Winget não encontrado. Iniciando instalação automática do App Installer...'
        if (-not (Install-WingetBootstrap)) {
            throw 'Winget indisponível; não foi possível atualizar os aplicativos.'
        }
        $wg = Test-WingetAvailable
        if (-not $wg.Available) {
            throw 'Winget indisponível após o bootstrap.'
        }
    }

    $commands = New-Object 'System.Collections.Generic.List[pscustomobject]'
    if ($All) {
        [void]$commands.Add([pscustomobject]@{
            Label     = 'Winget upgrade --all'
            Arguments = @('upgrade', '--all', '--include-unknown', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
        })
    }
    else {
        foreach ($id in $cleanIds) {
            [void]$commands.Add([pscustomobject]@{
                Label     = ("Winget upgrade {0}" -f $id)
                Arguments = @('upgrade', '--id', $id, '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
            })
        }
    }

    $successCodes = @(0, -1978335189, 3010)
    Invoke-Mutation -Description 'Atualizar aplicativos via Winget' -Action {
        foreach ($command in $commands) {
            $exitCode = Invoke-OptiKitWingetCommand -WingetPath $wg.Path -Arguments $command.Arguments -Label $command.Label
            if ($successCodes -notcontains $exitCode) {
                throw ("{0} retornou código {1}." -f $command.Label, $exitCode)
            }
            if ($exitCode -eq -1978335189) {
                Write-OptimizerLog -Level INFO -Message ("{0}: nenhuma atualização aplicável." -f $command.Label)
            }
            elseif ($exitCode -eq 3010) {
                Write-OptimizerLog -Level OK -Message ("{0}: atualizado; reinicialização recomendada." -f $command.Label)
            }
            else {
                Write-OptimizerLog -Level OK -Message ("{0}: concluído." -f $command.Label)
            }
        }
    } | Out-Null

    return $true
}
