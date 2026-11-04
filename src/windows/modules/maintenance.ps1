# Ferramentas de Manutenção e Reparo: Reset de Rede/DNS, SFC/DISM com cancelamento e Limpeza de Temporários

#region dev-only
if (-not (Get-Command Write-OptimizerLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\core\logger.ps1')
}
if (-not (Get-Command Get-RegistryEntryState -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'tweak-engine.ps1')
}
if (-not (Get-Command Read-OptiKitStateFile -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\core\backup.ps1')
}
#endregion

function Invoke-NetworkReset {
    [CmdletBinding()]
    param()

    Invoke-Mutation -Description 'Resetar pilha de rede (Winsock, TCP/IP e Cache DNS)' -Action {
        Write-OptimizerLog -Level INFO -Message 'Limpando cache de resolução DNS (ipconfig /flushdns)...'
        Start-Process -FilePath 'ipconfig.exe' -ArgumentList '/flushdns' -NoNewWindow -Wait | Out-Null

        Write-OptimizerLog -Level INFO -Message 'Redefinindo catálogo Winsock (netsh winsock reset)...'
        Start-Process -FilePath 'netsh.exe' -ArgumentList @('winsock', 'reset') -NoNewWindow -Wait | Out-Null

        Write-OptimizerLog -Level INFO -Message 'Redefinindo pilha TCP/IP (netsh int ip reset)...'
        Start-Process -FilePath 'netsh.exe' -ArgumentList @('int', 'ip', 'reset') -NoNewWindow -Wait | Out-Null

        Write-OptimizerLog -Level OK -Message 'Pilha de rede e DNS redefinidos com sucesso. Reinicie o computador para concluir.'
    } | Out-Null
}

function Invoke-CancelableProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$StepName
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    [void]$proc.Start()
    while (-not $proc.HasExited) {
        $cancel = ($script:OptiKit -and $script:OptiKit.CancelRequest) -or
                  ($script:OptiKit -and $script:OptiKit.SyncHash -and $script:OptiKit.SyncHash.CancelRequest)
        if ($cancel) {
            try {
                $proc.Kill()
            }
            catch {
                Write-Verbose ("Erro ao encerrar processo cancelado: {0}" -f $_.Exception.Message)
            }
            Write-OptimizerLog -Level WARN -Message ("Execução de {0} cancelada pelo usuário." -f $StepName)
            return $false
        }

        while (-not $proc.StandardOutput.EndOfStream) {
            $line = $proc.StandardOutput.ReadLine()
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $cleanLine = ($line -replace "`0", '').Trim()
                if ($cleanLine.Length -gt 0) {
                    Write-OptimizerLog -Level INFO -Message ("[{0}] {1}" -f $StepName, $cleanLine)
                }
            }
        }
        Start-Sleep -Milliseconds 200
    }

    return ($proc.ExitCode -eq 0)
}

function Invoke-SystemIntegrityRepair {
    [CmdletBinding()]
    param()

    if ($script:OptiKit) {
        $script:OptiKit.CancelRequest = $false
        if ($script:OptiKit.SyncHash) {
            $script:OptiKit.SyncHash.CancelRequest = $false
        }
    }

    Invoke-Mutation -Description 'Executar verificação e reparo de imagem do sistema (DISM /RestoreHealth + SFC /scannow)' -Action {
        Write-OptimizerLog -Level INFO -Message 'Etapa 1/2: Executando DISM /Online /Cleanup-Image /RestoreHealth (pode levar de 5 a 15 minutos)...'
        $dismOk = Invoke-CancelableProcess -FilePath 'DISM.exe' -Arguments '/Online /Cleanup-Image /RestoreHealth' -StepName 'DISM'
        if (-not $dismOk) {
            return
        }

        Write-OptimizerLog -Level INFO -Message 'Etapa 2/2: Executando SFC /scannow...'
        [void](Invoke-CancelableProcess -FilePath 'sfc.exe' -Arguments '/scannow' -StepName 'SFC')
        Write-OptimizerLog -Level OK -Message 'Verificação de integridade SFC/DISM finalizada.'
    } | Out-Null
}

function Clear-TemporaryFiles {
    [CmdletBinding()]
    param(
        [string[]]$TargetDirectories
    )

    if (-not $TargetDirectories -or $TargetDirectories.Count -eq 0) {
        $TargetDirectories = @(
            $env:TEMP,
            (Join-Path $env:SystemRoot 'Temp')
        ) | Select-Object -Unique
    }

    Invoke-Mutation -Description 'Limpar arquivos temporários do usuário (%TEMP%) e do sistema (Windows\Temp)' -Action {
        $freedBytes = [int64]0
        $deletedFiles = 0

        foreach ($dir in $TargetDirectories) {
            if (-not $dir -or -not (Test-Path -LiteralPath $dir)) {
                continue
            }

            $files = Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                $len = $f.Length
                try {
                    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                    $freedBytes += $len
                    $deletedFiles++
                }
                catch {
                    Write-Verbose ("Arquivo temporário em uso (ignorado): {0}" -f $f.FullName)
                }
            }
        }

        $freedMb = [math]::Round(($freedBytes / 1MB), 2)
        Write-OptimizerLog -Level OK -Message ("Limpeza concluída: {0} arquivos temporários removidos ({1} MB liberados)." -f $deletedFiles, $freedMb)
    } | Out-Null
}

function Set-OptiKitTargetRelease {
    [CmdletBinding()]
    param()

    $wuKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    $displayVersion = [string]$cv.DisplayVersion
    if ([string]::IsNullOrWhiteSpace($displayVersion)) {
        throw 'Não foi possível ler DisplayVersion do Windows.'
    }

    $productVersion = if ([string]$cv.ProductName -match 'Windows 11') {
        'Windows 11'
    }
    elseif ([string]$cv.ProductName -match 'Windows 10') {
        'Windows 10'
    }
    else {
        throw 'ProductName do Windows não reconhecido.'
    }

    $captured = New-Object 'System.Collections.Generic.List[hashtable]'
    foreach ($name in @('ProductVersion', 'TargetReleaseVersion', 'TargetReleaseVersionInfo')) {
        $state = Get-RegistryEntryState -Path $wuKey -Name $name -FallbackType 'DWord'
        [void]$captured.Add(@{
            kind       = 'registry'
            path       = $wuKey
            name       = $name
            keyExisted = [bool]$state.KeyExisted
            existed    = [bool]$state.ValueExisted
            type       = $state.Type
            value      = $state.Value
        })
    }
    Save-CapturedState -Id 'TargetReleaseVersion' -CapturedItems $captured.ToArray()

    Invoke-Mutation -Description ("Fixar feature updates em {0} ({1})" -f $displayVersion, $productVersion) -Action {
        Set-RegistryEntryValue -Path $wuKey -Name 'ProductVersion' -Type 'String' -Value $productVersion
        Set-RegistryEntryValue -Path $wuKey -Name 'TargetReleaseVersion' -Type 'DWord' -Value 1
        Set-RegistryEntryValue -Path $wuKey -Name 'TargetReleaseVersionInfo' -Type 'String' -Value $displayVersion
    } | Out-Null
}

function Restore-OptiKitTargetRelease {
    [CmdletBinding()]
    param()

    $captured = Get-CapturedState -Id 'TargetReleaseVersion'
    $capturedList = if ($captured -and $captured.captured) { @($captured.captured) } else { @() }

    Invoke-Mutation -Description 'Remover fixação de feature update (TargetReleaseVersion)' -Action {
        if ($capturedList.Count -gt 0) {
            foreach ($item in $capturedList) {
                if ($item.existed) {
                    Set-RegistryEntryValue -Path $item.path -Name $item.name -Type $item.type -Value $item.value
                }
                else {
                    Set-RegistryEntryValue -Path $item.path -Name $item.name -Type $item.type -Value '<RemoveEntry>'
                }
            }
        }
        else {
            $wuKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
            foreach ($name in @('ProductVersion', 'TargetReleaseVersion', 'TargetReleaseVersionInfo')) {
                Set-RegistryEntryValue -Path $wuKey -Name $name -Type 'String' -Value '<RemoveEntry>'
            }
        }
    } | Out-Null

    Remove-CapturedState -Id 'TargetReleaseVersion'
}

function Test-OptiKitTargetRelease {
    [CmdletBinding()]
    param()

    $wuKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $target = Get-RegistryEntryState -Path $wuKey -Name 'TargetReleaseVersion' -FallbackType 'DWord'
    $info = Get-RegistryEntryState -Path $wuKey -Name 'TargetReleaseVersionInfo' -FallbackType 'String'
    return ($target.ValueExisted -and ([int]$target.Value -eq 1) -and $info.ValueExisted -and -not [string]::IsNullOrWhiteSpace([string]$info.Value))
}

function Disable-OptiKitReservedStorage {
    [CmdletBinding()]
    param()

    $previous = $null
    try {
        if (Get-Command Get-WindowsReservedStorageState -ErrorAction SilentlyContinue) {
            $previous = [string](Get-WindowsReservedStorageState -ErrorAction Stop)
        }
    }
    catch {
        Write-Verbose ("Estado do Armazenamento Reservado indisponível: {0}" -f $_.Exception.Message)
    }

    $wasEnabled = $true
    if ($previous -and $previous -match '(?i)Disabled|Desabilitado') {
        $wasEnabled = $false
    }

    Save-CapturedState -Id 'ReservedStorage' -CapturedItems @(
        @{ kind = 'reservedStorage'; wasEnabled = $wasEnabled; previous = $previous }
    )

    Invoke-Mutation -Description 'Desativar Armazenamento Reservado do Windows via DISM' -Action {
        $proc = Start-Process -FilePath 'DISM.exe' -ArgumentList @('/Online', '/Set-ReservedStorageState', '/State:Disabled') -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            throw ("DISM /Set-ReservedStorageState retornou código {0}" -f $proc.ExitCode)
        }
    } | Out-Null
}

function Enable-OptiKitReservedStorage {
    [CmdletBinding()]
    param()

    $captured = Get-CapturedState -Id 'ReservedStorage'
    $targetState = 'Enabled'
    if ($captured -and $captured.captured -and $captured.captured.Count -gt 0 -and $captured.captured[0].wasEnabled -eq $false) {
        $targetState = 'Disabled'
    }

    Invoke-Mutation -Description ("Restaurar Armazenamento Reservado para {0}" -f $targetState) -Action {
        $proc = Start-Process -FilePath 'DISM.exe' -ArgumentList @('/Online', '/Set-ReservedStorageState', ("/State:{0}" -f $targetState)) -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            throw ("DISM /Set-ReservedStorageState retornou código {0}" -f $proc.ExitCode)
        }
    } | Out-Null

    Remove-CapturedState -Id 'ReservedStorage'
}

function Test-OptiKitReservedStorage {
    [CmdletBinding()]
    param()

    try {
        if (Get-Command Get-WindowsReservedStorageState -ErrorAction SilentlyContinue) {
            $state = [string](Get-WindowsReservedStorageState -ErrorAction Stop)
            return ($state -match '(?i)Disabled|Desabilitado')
        }
    }
    catch {
        return $false
    }
    return $false
}

function Test-OptiKitUpdateAvailable {
    [CmdletBinding()]
    param(
        [string]$RepoSlug = $script:OptiKitRepo,
        [string]$CurrentVersion = $script:OptiKitVersion
    )

    if ([string]::IsNullOrWhiteSpace($RepoSlug) -or [string]::IsNullOrWhiteSpace($CurrentVersion)) {
        return $null
    }

    try {
        $url = "https://raw.githubusercontent.com/$RepoSlug/main/VERSION"
        $raw = (Invoke-RestMethod -Uri $url -TimeoutSec 5 -UseBasicParsing).Trim()
        $remote = [version]$raw
        $local = [version]$CurrentVersion
        if ($remote -gt $local) {
            return [pscustomobject]@{
                Available = $true
                Version   = $remote.ToString()
                Url       = "https://github.com/$RepoSlug/releases/latest"
            }
        }
    }
    catch {
        Write-Verbose ("Verificação de atualização indisponível: {0}" -f $_.Exception.Message)
    }
    return $null
}

function Export-OptiKitReport {
    [CmdletBinding()]
    param(
        [string]$OutputDirectory
    )

    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = Join-Path $script:OptiKit.DataRoot 'reports'
    }
    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path = Join-Path $OutputDirectory ("optikit-report-{0}.html" -f $timestamp)
    $hardware = Get-OptiKitHardware
    $state = Read-OptiKitStateFile
    $logLines = @($script:OptiKit.LogHistory)

    $encode = {
        param([string]$text)
        if ($null -eq $text) { return '' }
        return ($text -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;')
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!DOCTYPE html><html lang="pt-BR"><head><meta charset="utf-8"><title>OptiKit Report</title>')
    [void]$sb.AppendLine('<style>body{font-family:Segoe UI,Arial,sans-serif;background:#121212;color:#e4e4e7;padding:24px}table{border-collapse:collapse;width:100%;margin:12px 0}td,th{border:1px solid #3f3f46;padding:6px;text-align:left}th{background:#27272a;color:#00e5ff}pre{background:#0d0d10;padding:12px;overflow:auto;font-size:12px}h1,h2{color:#00e5ff}</style></head><body>')
    [void]$sb.AppendLine(("<h1>OptiKit v{0} — Relatório</h1>" -f (& $encode ([string]$script:OptiKitVersion))))
    [void]$sb.AppendLine(("<p><b>Data:</b> {0}<br><b>Hardware:</b> {1}</p>" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), (& $encode ([string]$hardware.Summary))))
    [void]$sb.AppendLine('<h2>Ajustes com estado capturado</h2><table><tr><th>ID</th><th>Aplicado em</th><th>Sessão</th></tr>')

    if ($state.Count -eq 0) {
        [void]$sb.AppendLine('<tr><td colspan="3">Nenhum estado capturado.</td></tr>')
    }
    else {
        foreach ($key in $state.Keys) {
            $record = $state[$key]
            [void]$sb.AppendLine(("<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>" -f (& $encode ([string]$key)), (& $encode ([string]$record.appliedAt)), (& $encode ([string]$record.session))))
        }
    }

    [void]$sb.AppendLine('</table><h2>Log da sessão</h2><pre>')
    [void]$sb.AppendLine((& $encode (($logLines -join [Environment]::NewLine))))
    [void]$sb.AppendLine('</pre></body></html>')

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($path, $sb.ToString(), $utf8Bom)
    Write-OptimizerLog -Level OK -Message ("Relatório exportado: {0}" -f $path)
    return $path
}
