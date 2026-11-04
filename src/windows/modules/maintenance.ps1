# Ferramentas de Manutenção e Reparo: Reset de Rede/DNS, SFC/DISM com cancelamento e Limpeza de Temporários

#region dev-only
if (-not (Get-Command Write-OptimizerLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\core\logger.ps1')
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
