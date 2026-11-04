# Sistema de logs, estado de execução e ponto único de mutação (DryRun / Auditoria)

if (-not $script:OptiKit) {
    $defaultRoot = Join-Path $env:ProgramData 'optikit'
    $script:OptiKit = @{
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
        ConsoleOutput = $false
        SessionCounts = @{ Applied = 0; Skipped = 0; Failed = 0 }
    }
}

function Initialize-OptiKitEnvironment {
    [CmdletBinding()]
    param(
        [string]$DataRoot,
        [switch]$DryRun,
        [hashtable]$SyncHash
    )

    if ($DataRoot) {
        $script:OptiKit.DataRoot   = $DataRoot
        $script:OptiKit.LogsDir    = Join-Path $DataRoot 'logs'
        $script:OptiKit.BackupsDir = Join-Path $DataRoot 'backups'
        $script:OptiKit.StateFile  = Join-Path $DataRoot 'state.json'
    }

    $script:OptiKit.SessionCounts = @{ Applied = 0; Skipped = 0; Failed = 0 }

    if ($PSBoundParameters.ContainsKey('DryRun')) {
        $script:OptiKit.DryRun = [bool]$DryRun
    }

    if ($SyncHash) {
        $script:OptiKit.SyncHash = $SyncHash
    }

    try {
        if (-not (Test-Path -LiteralPath $script:OptiKit.LogsDir)) {
            New-Item -Path $script:OptiKit.LogsDir -ItemType Directory -Force | Out-Null
        }
        if (-not (Test-Path -LiteralPath $script:OptiKit.BackupsDir)) {
            New-Item -Path $script:OptiKit.BackupsDir -ItemType Directory -Force | Out-Null
        }
    }
    catch {
        $fallbackRoot = Join-Path $env:TEMP 'optikit'
        $script:OptiKit.DataRoot   = $fallbackRoot
        $script:OptiKit.LogsDir    = Join-Path $fallbackRoot 'logs'
        $script:OptiKit.BackupsDir = Join-Path $fallbackRoot 'backups'
        $script:OptiKit.StateFile  = Join-Path $fallbackRoot 'state.json'
        New-Item -Path $script:OptiKit.LogsDir -ItemType Directory -Force | Out-Null
        New-Item -Path $script:OptiKit.BackupsDir -ItemType Directory -Force | Out-Null
    }

    if (-not $script:OptiKit.SessionId) {
        $script:OptiKit.SessionId = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    }
    $script:OptiKit.LogFile = Join-Path $script:OptiKit.LogsDir ("optikit_{0}.log" -f $script:OptiKit.SessionId)
    return $script:OptiKit
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

    if ($script:OptiKit -and $null -ne $script:OptiKit.LogHistory) {
        [void]$script:OptiKit.LogHistory.Add($line)
    }

    if ($script:OptiKit -and $script:OptiKit.LogFile) {
        try {
            $utf8Bom = New-Object System.Text.UTF8Encoding($true)
            [System.IO.File]::AppendAllText($script:OptiKit.LogFile, ($line + [Environment]::NewLine), $utf8Bom)
        }
        catch {
            Write-Verbose ("Falha ao gravar arquivo de log: {0}" -f $_.Exception.Message)
        }
    }

    if ($script:OptiKit -and $script:OptiKit.SyncHash) {
        $sync = $script:OptiKit.SyncHash
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

    if ($script:OptiKit -and $script:OptiKit.ConsoleOutput) {
        Write-Host $line
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

    if ($script:OptiKit -and $script:OptiKit.DryRun) {
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
