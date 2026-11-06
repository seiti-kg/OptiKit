# Testes do parser de benchmark do PresentMon e da tabela de comparação

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'src\windows\core\logger.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\modules\benchmark-engine.ps1')
}

Describe 'Benchmark PresentMon (benchmark-engine.ps1)' {
    It 'Deve calcular FPS médio, lows, frame time e GPU busy a partir do CSV' {
        $path = Join-Path $TestDrive 'benchmark.csv'
        $lines = New-Object 'System.Collections.Generic.List[string]'
        [void]$lines.Add('Application,ProcessID,MsBetweenPresents,MsGPUBusy')
        for ($i = 0; $i -lt 90; $i++) { [void]$lines.Add('game,123,10,8') }
        for ($i = 0; $i -lt 10; $i++) { [void]$lines.Add('game,123,20,16') }
        [System.IO.File]::WriteAllLines($path, $lines)

        $result = Get-OptiKitBenchmarkResult -CsvPath $path

        $result.Frames | Should -Be 100
        $result.AverageFps | Should -BeGreaterThan 90.90
        $result.AverageFps | Should -BeLessThan 90.92
        $result.OnePercentLow | Should -Be 50
        $result.PointOnePercentLow | Should -Be 50
        $result.FrameTimeP95Ms | Should -Be 20
        $result.FrameTimeP99Ms | Should -Be 20
        $result.GpuBusyAvgMs | Should -Be 8.8
        $result.DurationSeconds | Should -Be 1.1
    }

    It 'Deve ignorar linhas NA e exigir pelo menos 10 frames válidos' {
        $path = Join-Path $TestDrive 'benchmark-na.csv'
        $lines = New-Object 'System.Collections.Generic.List[string]'
        [void]$lines.Add('Application,ProcessID,MsBetweenPresents,MsGPUBusy')
        for ($i = 0; $i -lt 10; $i++) { [void]$lines.Add('game,123,10,8') }
        [void]$lines.Add('game,123,NA,NA')
        [System.IO.File]::WriteAllLines($path, $lines)

        $result = Get-OptiKitBenchmarkResult -CsvPath $path
        $result.Frames | Should -Be 10
        $result.AverageFps | Should -Be 100

        $empty = Join-Path $TestDrive 'benchmark-empty.csv'
        [System.IO.File]::WriteAllLines($empty, @('Application,ProcessID,MsBetweenPresents,MsGPUBusy', 'game,123,NA,NA'))
        { Get-OptiKitBenchmarkResult -CsvPath $empty } | Should -Throw '*sem frames válidos*'
    }

    It 'Deve comparar a captura atual com a anterior' {
        $current = [pscustomobject]@{
            AverageFps         = 100
            OnePercentLow      = 80
            PointOnePercentLow = 70
            FrameTimeP95Ms     = 12
            FrameTimeP99Ms     = 18
            GpuBusyAvgMs       = 9
            Frames             = 1000
            DurationSeconds    = 10
        }
        $previous = [pscustomobject]@{
            AverageFps         = 90
            OnePercentLow      = 70
            PointOnePercentLow = 60
            FrameTimeP95Ms     = 14
            FrameTimeP99Ms     = 20
            GpuBusyAvgMs       = 10
            Frames             = 1000
            DurationSeconds    = 10
        }

        $rows = @(Get-OptiKitBenchmarkComparisonRows -Current $current -Previous $previous)
        $rows.Count | Should -Be 8
        ($rows | Where-Object Metric -eq 'FPS médio').Delta | Should -Match '^\+10[.,]0$'
        ($rows | Where-Object Metric -eq 'Frame time P95').Delta | Should -Match '^-2[.,]00 ms$'
    }
}
