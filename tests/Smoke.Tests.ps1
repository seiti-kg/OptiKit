# Teste de fumaça (Smoke Test) da GUI WPF em modo -DryRun -SmokeTest

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:WinPs1Path = Join-Path $script:RepoRoot 'win.ps1'
}

Describe 'GUI WPF Smoke Test (win.ps1 -DryRun -SmokeTest)' {
    It 'Deve abrir a janela WPF, construir controles dos JSONs, rodar o state-checker no worker runspace e fechar com código 0' {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe"
        $psi.Arguments = ('-NoProfile -ExecutionPolicy Bypass -STA -File "{0}" -DryRun -SmokeTest -NoElevate' -f $script:WinPs1Path)
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        try {
            $exited = $proc.WaitForExit(40000)
            $exited | Should -BeTrue
            $proc.ExitCode | Should -Be 0
        }
        finally {
            if ($proc -and (-not $proc.HasExited)) {
                try { $proc.Kill() } catch { Write-Verbose $_.Exception.Message }
            }
        }
    }
}
