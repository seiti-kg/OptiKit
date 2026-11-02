# Ponto de Restauração, exportação de chaves (.reg) e persistência atômica de Undo (state.json)

#region dev-only
if (-not (Get-Command Write-OptimizerLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'logger.ps1')
}
#endregion

function New-RedimoBackupSession {
    [CmdletBinding()]
    param(
        [string]$SessionId
    )

    if (-not $script:Redimo) {
        Initialize-RedimoEnvironment | Out-Null
    }

    if ($SessionId) {
        $script:Redimo.SessionId = $SessionId
    }
    elseif (-not $script:Redimo.SessionId) {
        $script:Redimo.SessionId = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    }

    $sessionDir = Join-Path $script:Redimo.BackupsDir $script:Redimo.SessionId
    if (-not $script:Redimo.DryRun) {
        if (-not (Test-Path -LiteralPath $sessionDir)) {
            New-Item -Path $sessionDir -ItemType Directory -Force | Out-Null
        }
    }
    else {
        Write-OptimizerLog -Level DRYRUN -Message ("Criar diretório de sessão de backup: {0}" -f $sessionDir)
    }

    $script:Redimo.SessionDir = $sessionDir
    return $sessionDir
}

function ConvertTo-RegExePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PsPath
    )

    $clean = $PsPath.Trim()
    $clean = $clean -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
    $clean = $clean -replace '^HKEY_LOCAL_MACHINE\\', 'HKLM\'
    $clean = $clean -replace '^HKEY_CURRENT_USER\\', 'HKCU\'
    $clean = $clean -replace '^HKEY_CLASSES_ROOT\\', 'HKCR\'
    $clean = $clean -replace '^HKEY_USERS\\', 'HKU\'
    $clean = $clean -replace '^HKLM:\\?', 'HKLM\'
    $clean = $clean -replace '^HKCU:\\?', 'HKCU\'
    $clean = $clean -replace '^HKCR:\\?', 'HKCR\'
    $clean = $clean -replace '^HKU:\\?', 'HKU\'
    return $clean
}

function Export-RegistryKeyBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Paths,

        [string]$DestinationDir
    )

    if (-not $Paths -or $Paths.Count -eq 0) {
        return @()
    }

    if (-not $DestinationDir) {
        if (-not $script:Redimo.SessionDir) {
            New-RedimoBackupSession | Out-Null
        }
        $DestinationDir = $script:Redimo.SessionDir
    }

    $exportedFiles = New-Object 'System.Collections.Generic.List[string]'
    $uniquePaths = $Paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($psPath in $uniquePaths) {
        $regPath = ConvertTo-RegExePath -PsPath $psPath
        $safeName = ($regPath -replace '[\\/:*?"<>|\s\{\}]', '_') + '.reg'
        $outFile = Join-Path $DestinationDir $safeName

        if ($script:Redimo -and $script:Redimo.DryRun) {
            Write-OptimizerLog -Level DRYRUN -Message ("Exportar chave de registro '{0}' para '{1}'" -f $regPath, $outFile)
            [void]$exportedFiles.Add($outFile)
            continue
        }

        if (-not (Test-Path -LiteralPath $psPath)) {
            Write-OptimizerLog -Level INFO -Message ("Chave '{0}' ainda não existe no sistema (sem necessidade de export .reg)." -f $psPath)
            continue
        }

        try {
            if (-not (Test-Path -LiteralPath $DestinationDir)) {
                New-Item -Path $DestinationDir -ItemType Directory -Force | Out-Null
            }
            $proc = Start-Process -FilePath 'reg.exe' -ArgumentList @('export', $regPath, $outFile, '/y') -NoNewWindow -Wait -PassThru
            if ($proc.ExitCode -eq 0 -and (Test-Path -LiteralPath $outFile)) {
                Write-OptimizerLog -Level OK -Message ("Backup de registro salvo: {0}" -f $safeName)
                [void]$exportedFiles.Add($outFile)
            }
            else {
                Write-OptimizerLog -Level WARN -Message ("reg.exe export retornou código {0} para '{1}'" -f $proc.ExitCode, $regPath)
            }
        }
        catch {
            Write-OptimizerLog -Level WARN -Message ("Falha ao exportar '{0}': {1}" -f $regPath, $_.Exception.Message)
        }
    }

    return $exportedFiles.ToArray()
}

function Read-RedimoStateFile {
    [CmdletBinding()]
    param(
        [string]$StateFilePath
    )

    if (-not $StateFilePath) {
        $StateFilePath = $script:Redimo.StateFile
    }

    $result = @{}
    if (-not $StateFilePath -or -not (Test-Path -LiteralPath $StateFilePath)) {
        return $result
    }

    try {
        $raw = [System.IO.File]::ReadAllText($StateFilePath, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $result
        }
        $parsed = $raw | ConvertFrom-Json
        if ($null -ne $parsed) {
            foreach ($prop in $parsed.PSObject.Properties) {
                $result[$prop.Name] = $prop.Value
            }
        }
    }
    catch {
        Write-OptimizerLog -Level WARN -Message ("Não foi possível ler state.json em '{0}': {1}" -f $StateFilePath, $_.Exception.Message)
    }

    return $result
}

function Write-RedimoStateFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$StateData,

        [string]$StateFilePath
    )

    if (-not $StateFilePath) {
        $StateFilePath = $script:Redimo.StateFile
    }

    if ($script:Redimo -and $script:Redimo.DryRun) {
        Write-OptimizerLog -Level DRYRUN -Message ("Atualizar arquivo de estado '{0}' ({1} entradas)" -f $StateFilePath, $StateData.Count)
        return
    }

    $parentDir = Split-Path -Path $StateFilePath -Parent
    if ($parentDir -and -not (Test-Path -LiteralPath $parentDir)) {
        New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
    }

    $tmpFile = "{0}.{1}.tmp" -f $StateFilePath, [Guid]::NewGuid().ToString('N')
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    $json = [pscustomobject]$StateData | ConvertTo-Json -Depth 10

    try {
        [System.IO.File]::WriteAllText($tmpFile, $json, $utf8Bom)
        if (Test-Path -LiteralPath $StateFilePath) {
            Remove-Item -LiteralPath $StateFilePath -Force
        }
        Move-Item -LiteralPath $tmpFile -Destination $StateFilePath -Force

        if ($script:Redimo -and $script:Redimo.SessionDir -and (Test-Path -LiteralPath $script:Redimo.SessionDir)) {
            $snapshotPath = Join-Path $script:Redimo.SessionDir 'state-snapshot.json'
            [System.IO.File]::WriteAllText($snapshotPath, $json, $utf8Bom)
        }
    }
    catch {
        if (Test-Path -LiteralPath $tmpFile) {
            Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
        }
        Write-OptimizerLog -Level WARN -Message ("Falha na escrita atômica do state.json: {0}" -f $_.Exception.Message)
        throw
    }
}

function Save-CapturedState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$CapturedItems,

        [switch]$ForceOverwrite,
        [string]$StateFilePath
    )

    if ($script:Redimo -and $script:Redimo.DryRun) {
        Write-OptimizerLog -Level DRYRUN -Message ("Capturar estado original para '{0}' ({1} itens)" -f $Id, $CapturedItems.Count)
        return
    }

    $state = Read-RedimoStateFile -StateFilePath $StateFilePath
    if ($state.ContainsKey($Id) -and -not $ForceOverwrite) {
        Write-OptimizerLog -Level INFO -Message ("Estado original de '{0}' já está preservado no state.json (first-capture-wins)." -f $Id)
        return
    }

    $state[$Id] = [pscustomobject]@{
        appliedAt = (Get-Date -Format 'o')
        session   = if ($script:Redimo -and $script:Redimo.SessionId) { $script:Redimo.SessionId } else { (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') }
        captured  = @($CapturedItems)
    }

    Write-RedimoStateFile -StateData $state -StateFilePath $StateFilePath
}

function Get-CapturedState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [string]$StateFilePath
    )

    $state = Read-RedimoStateFile -StateFilePath $StateFilePath
    if ($state.ContainsKey($Id)) {
        return $state[$Id]
    }
    return $null
}

function Remove-CapturedState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [string]$StateFilePath
    )

    if ($script:Redimo -and $script:Redimo.DryRun) {
        Write-OptimizerLog -Level DRYRUN -Message ("Remover entrada '{0}' do state.json após Undo" -f $Id)
        return
    }

    $state = Read-RedimoStateFile -StateFilePath $StateFilePath
    if ($state.ContainsKey($Id)) {
        [void]$state.Remove($Id)
        Write-RedimoStateFile -StateData $state -StateFilePath $StateFilePath
    }
}

function New-RedimoRestorePoint {
    [CmdletBinding()]
    param(
        [string]$Description = 'redimo - Antes de aplicar otimizações',
        [scriptblock]$ConfirmEnableProtection
    )

    if ($script:Redimo -and $script:Redimo.DryRun) {
        Write-OptimizerLog -Level DRYRUN -Message ("Criar Ponto de Restauração do Sistema: '{0}'" -f $Description)
        return $true
    }

    $srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $hadFreqValue = $false
    $prevFreqValue = $null

    try {
        $rpInterval = 0
        if (Test-Path -LiteralPath $srKey) {
            $srProps = Get-ItemProperty -LiteralPath $srKey -ErrorAction SilentlyContinue
            if ($null -ne $srProps -and $null -ne $srProps.RPSessionInterval) {
                $rpInterval = [int]$srProps.RPSessionInterval
            }
            if ($null -ne $srProps -and ($srProps.PSObject.Properties.Name -contains 'SystemRestorePointCreationFrequency')) {
                $hadFreqValue = $true
                $prevFreqValue = $srProps.SystemRestorePointCreationFrequency
            }
        }

        if ($rpInterval -eq 0) {
            $shouldEnable = $false
            if ($ConfirmEnableProtection) {
                $shouldEnable = [bool](& $ConfirmEnableProtection)
            }
            if ($shouldEnable) {
                Write-OptimizerLog -Level INFO -Message 'Ativando Proteção do Sistema na unidade C:\...'
                Enable-ComputerRestore -Drive 'C:\' -ErrorAction Stop
            }
            else {
                Write-OptimizerLog -Level WARN -Message 'Proteção do Sistema desativada em C:\. Seguindo com backup .reg e state.json.'
                return $false
            }
        }

        if (-not (Test-Path -LiteralPath $srKey)) {
            New-Item -Path $srKey -Force | Out-Null
        }
        Set-ItemProperty -LiteralPath $srKey -Name 'SystemRestorePointCreationFrequency' -Value 0 -Type DWord -ErrorAction Stop

        Write-OptimizerLog -Level INFO -Message ("Criando Ponto de Restauração: '{0}'..." -f $Description)
        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-OptimizerLog -Level OK -Message 'Ponto de Restauração do Sistema criado com sucesso.'
        return $true
    }
    catch {
        Write-OptimizerLog -Level WARN -Message ("Não foi possível criar Ponto de Restauração ({0}). Os backups .reg e state.json continuam ativos." -f $_.Exception.Message)
        return $false
    }
    finally {
        try {
            if (Test-Path -LiteralPath $srKey) {
                if ($hadFreqValue) {
                    Set-ItemProperty -LiteralPath $srKey -Name 'SystemRestorePointCreationFrequency' -Value $prevFreqValue -Type DWord -ErrorAction SilentlyContinue
                }
                else {
                    Remove-ItemProperty -LiteralPath $srKey -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue
                }
            }
        }
        catch {
            Write-Verbose ("Erro ao restaurar SystemRestorePointCreationFrequency: {0}" -f $_.Exception.Message)
        }
    }
}
