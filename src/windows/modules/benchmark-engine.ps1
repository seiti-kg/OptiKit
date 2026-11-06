# Benchmark de jogos via PresentMon: captura, analise de frame time e historico local

$script:OptiKitPresentMonVersion = '2.6.0'
$script:OptiKitPresentMonUrl = 'https://github.com/GameTechDev/PresentMon/releases/download/v2.6.0/PresentMon-2.6.0-x64.exe'
$script:OptiKitPresentMonSha256 = 'B2A706BC6AD475749E3B7E3409263AA1E6906D45BDCF993F6DBC0F660188F1AF'

function Get-OptiKitBenchmarkDirectory {
    [CmdletBinding()]
    param()

    $root = if ($script:OptiKit -and $script:OptiKit.DataRoot) { [string]$script:OptiKit.DataRoot } else { Join-Path $env:ProgramData 'optikit' }
    $path = Join-Path $root 'benchmarks'
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
    }
    return $path
}

function Get-OptiKitPresentMonPath {
    [CmdletBinding()]
    param()

    $root = if ($script:OptiKit -and $script:OptiKit.DataRoot) { [string]$script:OptiKit.DataRoot } else { Join-Path $env:ProgramData 'optikit' }
    $toolsDir = Join-Path $root 'tools'
    if (-not (Test-Path -LiteralPath $toolsDir)) {
        New-Item -Path $toolsDir -ItemType Directory -Force | Out-Null
    }

    $target = Join-Path $toolsDir 'PresentMon-2.6.0-x64.exe'
    if (Test-Path -LiteralPath $target) {
        try {
            $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($hash -ieq $script:OptiKitPresentMonSha256) {
                return $target
            }
            Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Verbose ("Falha ao validar o PresentMon existente: {0}" -f $_.Exception.Message)
        }
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $download = "$target.download"
    try {
        Invoke-WebRequest -Uri $script:OptiKitPresentMonUrl -OutFile $download -UseBasicParsing -ErrorAction Stop
        $hash = (Get-FileHash -LiteralPath $download -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($hash -ine $script:OptiKitPresentMonSha256) {
            Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue
            throw 'Falha de integridade ao baixar o PresentMon 2.6.0.'
        }
        Move-Item -LiteralPath $download -Destination $target -Force
        Unblock-File -LiteralPath $target -ErrorAction SilentlyContinue
        Write-OptimizerLog -Level INFO -Message ("PresentMon {0} baixado e verificado." -f $script:OptiKitPresentMonVersion)
        return $target
    }
    catch {
        Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue
        if ($_.Exception.Message -like 'Falha de integridade*') { throw }
        throw ("Não foi possível baixar o PresentMon 2.6.0: {0}" -f $_.Exception.Message)
    }
}

function Start-OptiKitBenchmark {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProcessName,
        [int]$DurationSeconds = 30
    )

    $procName = [System.IO.Path]::GetFileNameWithoutExtension($ProcessName)
    if ([string]::IsNullOrWhiteSpace($procName)) {
        throw 'Informe o processo do jogo.'
    }
    if ($DurationSeconds -lt 5) {
        throw 'A duração mínima do benchmark é de 5 segundos.'
    }

    $process = Get-Process -Name $procName -ErrorAction Stop | Select-Object -First 1
    if (-not $process) {
        throw ("Processo '{0}' não encontrado." -f $procName)
    }

    $exe = Get-OptiKitPresentMonPath
    $dir = Get-OptiKitBenchmarkDirectory
    $base = 'benchmark_{0}_{1}' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), ([Guid]::NewGuid().ToString('N').Substring(0, 8))
    $csv = Join-Path $dir "$base.csv"
    $json = Join-Path $dir "$base.json"

    $presentMonArgs = @(
        '--process_name', ($procName + '.exe'),
        '--output_file', ('"{0}"' -f $csv),
        '--timed', [string]$DurationSeconds,
        '--terminate_after_timed',
        '--no_console_stats',
        '--session_name', 'OptiKitBenchmark',
        '--stop_existing_session'
    )
    $presentMon = Start-Process -FilePath $exe -ArgumentList $presentMonArgs -PassThru -WindowStyle Hidden
    Write-OptimizerLog -Level INFO -Message ("Benchmark iniciado para '{0}' por {1}s." -f $procName, $DurationSeconds)

    return [pscustomobject]@{
        Process         = $presentMon
        ProcessName     = $procName
        CsvPath         = $csv
        JsonPath        = $json
        DurationSeconds = $DurationSeconds
        StartedAt       = Get-Date
    }
}

function Stop-OptiKitBenchmark {
    [CmdletBinding()]
    param(
        [System.Diagnostics.Process]$Process
    )

    if ($null -eq $Process) { return }
    try {
        if (-not $Process.HasExited) {
            $Process.Kill()
            [void]$Process.WaitForExit(5000)
        }
    }
    catch {
        Write-Verbose ("Falha ao encerrar o PresentMon: {0}" -f $_.Exception.Message)
    }
}

function Get-OptiKitBenchmarkResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CsvPath
    )

    $rows = @(Import-Csv -LiteralPath $CsvPath -ErrorAction Stop)
    if ($rows.Count -eq 0) {
        throw 'CSV de benchmark sem frames válidos.'
    }
    if (-not $rows[0].PSObject.Properties['MsBetweenPresents']) {
        throw 'CSV de benchmark sem coluna MsBetweenPresents.'
    }

    $frameTimes = New-Object 'System.Collections.Generic.List[double]'
    $gpuValues = New-Object 'System.Collections.Generic.List[double]'
    foreach ($row in $rows) {
        $rawFrame = [string]$row.MsBetweenPresents
        $frameMs = 0.0
        if ([double]::TryParse($rawFrame, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$frameMs) -and $frameMs -gt 0) {
            [void]$frameTimes.Add($frameMs)
        }

        $gpuProp = $row.PSObject.Properties['MsGPUBusy']
        if ($gpuProp) {
            $rawGpu = [string]$gpuProp.Value
            $gpuMs = 0.0
            if ([double]::TryParse($rawGpu, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$gpuMs) -and $gpuMs -ge 0) {
                [void]$gpuValues.Add($gpuMs)
            }
        }
    }

    $count = $frameTimes.Count
    if ($count -lt 10) {
        throw 'CSV de benchmark sem frames válidos.'
    }

    $avgMs = ($frameTimes | Measure-Object -Average).Average
    $slowest = @($frameTimes | Sort-Object -Descending)
    $oneCount = [Math]::Max(1, [int][Math]::Ceiling($count * 0.01))
    $pointOneCount = [Math]::Max(1, [int][Math]::Ceiling($count * 0.001))
    $oneAvgMs = ($slowest[0..($oneCount - 1)] | Measure-Object -Average).Average
    $pointOneAvgMs = ($slowest[0..($pointOneCount - 1)] | Measure-Object -Average).Average
    $p95Index = [Math]::Max(0, [int][Math]::Ceiling($count * 0.05) - 1)
    $p99Index = [Math]::Max(0, [int][Math]::Ceiling($count * 0.01) - 1)
    $gpuBusy = if ($gpuValues.Count -gt 0) { ($gpuValues | Measure-Object -Average).Average } else { $null }

    return [pscustomobject]@{
        AverageFps          = (1000 / $avgMs)
        OnePercentLow       = (1000 / $oneAvgMs)
        PointOnePercentLow  = (1000 / $pointOneAvgMs)
        FrameTimeP95Ms      = [double]$slowest[$p95Index]
        FrameTimeP99Ms      = [double]$slowest[$p99Index]
        GpuBusyAvgMs        = $gpuBusy
        Frames              = $count
        DurationSeconds     = (($frameTimes | Measure-Object -Sum).Sum / 1000)
        CsvPath             = $CsvPath
    }
}

function Export-OptiKitBenchmarkResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$Result,
        [Parameter(Mandatory = $true)][string]$ProcessName,
        [Parameter(Mandatory = $true)][string]$CsvPath,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )

    $version = if ($script:OptiKitVersion) { [string]$script:OptiKitVersion } else { '0.3.0' }
    $payload = [pscustomobject]@{
        Version            = $version
        ProcessName        = $ProcessName
        CapturedAt         = (Get-Date).ToString('o')
        CsvPath            = $CsvPath
        AverageFps         = $Result.AverageFps
        OnePercentLow      = $Result.OnePercentLow
        PointOnePercentLow = $Result.PointOnePercentLow
        FrameTimeP95Ms     = $Result.FrameTimeP95Ms
        FrameTimeP99Ms     = $Result.FrameTimeP99Ms
        GpuBusyAvgMs       = $Result.GpuBusyAvgMs
        Frames             = $Result.Frames
        DurationSeconds    = $Result.DurationSeconds
    }
    $json = $payload | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($OutputPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    return $OutputPath
}

function Get-OptiKitBenchmarkComparisonRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$Current,
        [pscustomobject]$Previous
    )

    $formatNumber = {
        param($Value, [string]$Format)
        if ($null -eq $Value) { return '—' }
        return ($Format -f [double]$Value)
    }
    $formatDelta = {
        param($CurrentValue, $PreviousValue, [string]$Format)
        if ($null -eq $PreviousValue -or $null -eq $CurrentValue) { return '—' }
        $delta = [double]$CurrentValue - [double]$PreviousValue
        $text = $Format -f [Math]::Abs($delta)
        if ($delta -ge 0) { return "+$text" }
        return "-$text"
    }

    $rows = New-Object 'System.Collections.Generic.List[object]'
    $definitions = @(
        @{ Metric = 'FPS médio'; Current = $Current.AverageFps; Previous = if ($Previous) { $Previous.AverageFps } else { $null }; Format = '{0:N1}'; DeltaFormat = '{0:N1}' },
        @{ Metric = '1% low'; Current = $Current.OnePercentLow; Previous = if ($Previous) { $Previous.OnePercentLow } else { $null }; Format = '{0:N1}'; DeltaFormat = '{0:N1}' },
        @{ Metric = '0.1% low'; Current = $Current.PointOnePercentLow; Previous = if ($Previous) { $Previous.PointOnePercentLow } else { $null }; Format = '{0:N1}'; DeltaFormat = '{0:N1}' },
        @{ Metric = 'Frame time P95'; Current = $Current.FrameTimeP95Ms; Previous = if ($Previous) { $Previous.FrameTimeP95Ms } else { $null }; Format = '{0:N2} ms'; DeltaFormat = '{0:N2} ms' },
        @{ Metric = 'Frame time P99'; Current = $Current.FrameTimeP99Ms; Previous = if ($Previous) { $Previous.FrameTimeP99Ms } else { $null }; Format = '{0:N2} ms'; DeltaFormat = '{0:N2} ms' },
        @{ Metric = 'GPU busy médio'; Current = $Current.GpuBusyAvgMs; Previous = if ($Previous) { $Previous.GpuBusyAvgMs } else { $null }; Format = '{0:N2} ms'; DeltaFormat = '{0:N2} ms' },
        @{ Metric = 'Frames'; Current = $Current.Frames; Previous = if ($Previous) { $Previous.Frames } else { $null }; Format = '{0:N0}'; DeltaFormat = '{0:N0}' },
        @{ Metric = 'Duração'; Current = $Current.DurationSeconds; Previous = if ($Previous) { $Previous.DurationSeconds } else { $null }; Format = '{0:N1} s'; DeltaFormat = '{0:N1} s' }
    )

    foreach ($definition in $definitions) {
        [void]$rows.Add([pscustomobject]@{
            Metric   = [string]$definition.Metric
            Current  = (& $formatNumber $definition.Current $definition.Format)
            Previous = (& $formatNumber $definition.Previous $definition.Format)
            Delta    = (& $formatDelta $definition.Current $definition.Previous $definition.DeltaFormat)
        })
    }
    return $rows.ToArray()
}

function Get-OptiKitLatestBenchmark {
    [CmdletBinding()]
    param(
        [string]$ExcludePath,
        [Parameter(Mandatory = $true)][string]$ProcessName
    )

    $dir = Get-OptiKitBenchmarkDirectory
    $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $ExcludePath } |
        Sort-Object LastWriteTime -Descending)

    foreach ($file in $files) {
        try {
            $item = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($item.ProcessName -and ([string]$item.ProcessName -ieq $ProcessName)) {
                return $item
            }
        }
        catch {
            Write-OptimizerLog -Level WARN -Message ("Benchmark anterior inválido ignorado: {0}" -f $file.Name)
        }
    }
    return $null
}
