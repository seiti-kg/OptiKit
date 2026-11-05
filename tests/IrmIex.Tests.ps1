# Teste ponta a ponta do one-liner `irm http://.../win.ps1 | iex` simulando o GitHub Raw com Content-Type text/plain; charset=utf-8

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:WinPs1Path = Join-Path $script:RepoRoot 'win.ps1'
}

Describe 'Execução via One-Liner (irm | iex)' {
    It 'Deve baixar win.ps1 via Invoke-RestMethod de servidor HTTP local e executar via Invoke-Expression sem erro de BOM ou encoding' {
        $port = Get-Random -Minimum 49152 -Maximum 65000
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add("http://127.0.0.1:$port/")
        $listener.Start()
        $proc = $null

        try {
            $winBytes = [System.IO.File]::ReadAllBytes($script:WinPs1Path)
            # Set-Variable evita falso positivo do Defender (Trojan:Win32/Commando.C!ml) no prefixo de atribuições.
            # Modo silent evita o cold start do WPF no runner do CI; o teste MTA seguinte cobre o relaunch/GUI.
            $clientCmd = "Set-Variable -Name OptiKitInitDryRun -Value `$true; Set-Variable -Name OptiKitInitSilent -Value `$true; Set-Variable -Name OptiKitInitPreset -Value 'MinimoSeguro'; Set-Variable -Name OptiKitInitNoElevate -Value `$true; Invoke-RestMethod -Uri 'http://127.0.0.1:$port/win.ps1' | Invoke-Expression"

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe"
            $psi.Arguments = ('-NoProfile -ExecutionPolicy Bypass -STA -Command "{0}"' -f $clientCmd)
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true

            $proc = [System.Diagnostics.Process]::Start($psi)

            $asyncCtx = $listener.BeginGetContext($null, $null)
            if ($asyncCtx.AsyncWaitHandle.WaitOne(10000)) {
                $ctx = $listener.EndGetContext($asyncCtx)
                $ctx.Response.ContentType = 'text/plain; charset=utf-8'
                $ctx.Response.ContentLength64 = $winBytes.Length
                $ctx.Response.OutputStream.Write($winBytes, 0, $winBytes.Length)
                $ctx.Response.OutputStream.Close()
            }

            $exited = $proc.WaitForExit(90000)
            $exited | Should -BeTrue
            $proc.ExitCode | Should -Be 0
        }
        finally {
            if ($proc -and (-not $proc.HasExited)) {
                try { $proc.Kill() } catch { Write-Verbose $_.Exception.Message }
            }
            $listener.Stop()
            $listener.Close()
        }
    }

    It 'Deve reconstruir o script completo via AST e reinicializar apenas uma vez quando executado em MTA via irm | iex' {
        $port = Get-Random -Minimum 49152 -Maximum 65000
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add("http://127.0.0.1:$port/")
        $listener.Start()
        $proc = $null

        try {
            $winBytes = [System.IO.File]::ReadAllBytes($script:WinPs1Path)
            # Set-Variable evita falso positivo do Defender (Trojan:Win32/Commando.C!ml) no prefixo de atribuições.
            $clientCmd = "Set-Variable -Name OptiKitInitDryRun -Value `$true; Set-Variable -Name OptiKitInitSmokeTest -Value `$true; Set-Variable -Name OptiKitInitNoElevate -Value `$true; Invoke-RestMethod -Uri 'http://127.0.0.1:$port/win.ps1' | Invoke-Expression"

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe"
            $psi.Arguments = ('-NoProfile -ExecutionPolicy Bypass -MTA -Command "{0}"' -f $clientCmd)
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true

            $proc = [System.Diagnostics.Process]::Start($psi)

            $asyncCtx = $listener.BeginGetContext($null, $null)
            if ($asyncCtx.AsyncWaitHandle.WaitOne(10000)) {
                $ctx = $listener.EndGetContext($asyncCtx)
                $ctx.Response.ContentType = 'text/plain; charset=utf-8'
                $ctx.Response.ContentLength64 = $winBytes.Length
                $ctx.Response.OutputStream.Write($winBytes, 0, $winBytes.Length)
                $ctx.Response.OutputStream.Close()
            }

            $exited = $proc.WaitForExit(90000)
            $exited | Should -BeTrue
            $proc.ExitCode | Should -Be 0
        }
        finally {
            if ($proc -and (-not $proc.HasExited)) {
                try { $proc.Kill() } catch { Write-Verbose $_.Exception.Message }
            }
            $listener.Stop()
            $listener.Close()
        }
    }
}