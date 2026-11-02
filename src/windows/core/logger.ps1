# Sistema de logs, estado de execução e ponto único de mutação (DryRun / Auditoria)

if (-not $script:Redimo) {
    $defaultRoot = Join-Path $env:ProgramData 'redimo'
    $script:Redimo = @{
        DataRoot      = $defaultRoot
        LogsDir       = Join-Path $defaultRoot 'logs'
        BackupsDir    = Join-Path $defaultRoot 'backups'
        StateFile     = Join-Path $defaultRoot 'state.json'
        LogFile       = $null
        DryRun        = $false
        SessionId     = (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')
        SessionDir    = $null
        SyncHash      = $null
        LogHistory    = New-Object 'System.Collections.Generic.List[string]'
        CancelRequest = $false
    }
}

function Initialize-RedimoEnvironment {
    [CmdletBinding()]
    param(
        [string]$DataRoot,
        [switch]$DryRun,
        [hashtable]$SyncHash
    )

    if ($DataRoot) {
        $script:Redimo.DataRoot   = $DataRoot
        $script:Redimo.LogsDir    = Join-Path $DataRoot 'logs'
        $script:Redimo.BackupsDir = Join-Path $DataRoot 'backups'
        $script:Redimo.StateFile  = Join-Path $DataRoot 'state.json'
    }

    if ($PSBoundParameters.ContainsKey('DryRun')) {
        $script:Redimo.DryRun = [bool]$DryRun
    }

    if ($SyncHash) {
        $script:Redimo.SyncHash = $SyncHash
    }

    try {
        if (-not (Test-Path -LiteralPath $script:Redimo.LogsDir)) {
            New-Item -Path $script:Redimo.LogsDir -ItemType Directory -Force | Out-Null
        }
        if (-not (Test-Path -LiteralPath $script:Redimo.BackupsDir)) {
            New-Item -Path $script:Redimo.BackupsDir -ItemType Directory -Force | Out-Null
        }
    }
    catch {
        $fallbackRoot = Join-Path $env:TEMP 'redimo'
        $script:Redimo.DataRoot   = $fallbackRoot
        $script:Redimo.LogsDir    = Join-Path $fallbackRoot 'logs'
        $script:Redimo.BackupsDir = Join-Path $fallbackRoot 'backups'
        $script:Redimo.StateFile  = Join-Path $fallbackRoot 'state.json'
        New-Item -Path $script:Redimo.LogsDir -ItemType Directory -Force | Out-Null
        New-Item -Path $script:Redimo.BackupsDir -ItemType Directory -Force | Out-Null
    }

    if (-not $script:Redimo.SessionId) {
        $script:Redimo.SessionId = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    }
    $script:Redimo.LogFile = Join-Path $script:Redimo.LogsDir ("redimo_{0}.log" -f $script:Redimo.SessionId)
    return $script:Redimo
}

function Write-OptimizerLog {
    [CmdletBinding()]
    param(
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'DRYRUN')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message
    )

    $timestamp = Get-Date -Format 'HH:mm:ss'
    $line = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message

    if ($script:Redimo -and $null -ne $script:Redimo.LogHistory) {
        [void]$script:Redimo.LogHistory.Add($line)
    }

    if ($script:Redimo -and $script:Redimo.LogFile) {
        try {
            $utf8Bom = New-Object System.Text.UTF8Encoding($true)
            [System.IO.File]::AppendAllText($script:Redimo.LogFile, ($line + [Environment]::NewLine), $utf8Bom)
        }
        catch {
            Write-Verbose ("Falha ao gravar arquivo de log: {0}" -f $_.Exception.Message)
        }
    }

    if ($script:Redimo -and $script:Redimo.SyncHash) {
        $sync = $script:Redimo.SyncHash
        if ($sync.LogQueue) {
            $entry = [pscustomobject]@{
                Timestamp = $timestamp
                Level     = $Level
                Message   = $Message
                Formatted = $line
            }
            $sync.LogQueue.Enqueue($entry)
        }
        $sync.StatusText = $Message
    }
}

function Invoke-Mutation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    if ($script:Redimo -and $script:Redimo.DryRun) {
        Write-OptimizerLog -Level DRYRUN -Message $Description
        return $true
    }

    try {
        & $Action
        Write-OptimizerLog -Level OK -Message $Description
        return $true
    }
    catch {
        Write-OptimizerLog -Level WARN -Message ("{0} — {1}" -f $Description, $_.Exception.Message)
        throw
    }
}
