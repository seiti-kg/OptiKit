# Ferramentas de processos: lista de apps com janela, suspensao e retomada

$script:OptiKitSuspendedProcesses = @{}

function Test-OptiKitProtectedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )

    return ($Name -match '(?i)^(System|Idle|csrss|wininit|winlogon|services|lsass|smss|svchost|dwm|explorer|SearchHost|StartMenuExperienceHost|ShellExperienceHost|ApplicationFrameHost|RuntimeBroker|TextInputHost|SecurityHealthService|MsMpEng|NisSrv|vgc|vgk|RiotClientServices|EasyAntiCheat|BEService|BattlEye|OptiKit|powershell|pwsh)$')
}

function Initialize-OptiKitProcessControl {
    [CmdletBinding()]
    param()

    if ('OptiKit.ProcessControl' -as [type]) { return }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace OptiKit {
    public static class ProcessControl {
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr handle);

        [DllImport("ntdll.dll")]
        public static extern uint NtSuspendProcess(IntPtr handle);

        [DllImport("ntdll.dll")]
        public static extern uint NtResumeProcess(IntPtr handle);
    }
}
'@
}

function Get-OptiKitBackgroundProcesses {
    [CmdletBinding()]
    param()

    $currentSession = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    $items = New-Object 'System.Collections.Generic.List[object]'
    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($process.Id -eq $PID) { continue }
        if ($process.MainWindowHandle -eq 0) { continue }
        if ($process.SessionId -ne $currentSession) { continue }
        if (Test-OptiKitProtectedProcess -Name $process.ProcessName) { continue }

        [void]$items.Add([pscustomobject]@{
            Id             = [int]$process.Id
            Name           = [string]$process.ProcessName
            Title          = [string]$process.MainWindowTitle
            WorkingSetMB   = [math]::Round($process.WorkingSet64 / 1MB, 0)
            IsSuspended    = $script:OptiKitSuspendedProcesses.ContainsKey([int]$process.Id)
        })
    }
    return @($items | Sort-Object -Property WorkingSetMB -Descending)
}

function Suspend-OptiKitProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$Id
    )

    $process = Get-Process -Id $Id -ErrorAction Stop
    if ($process.Id -eq $PID) { throw 'Não é possível suspender o próprio OptiKit.' }
    if (Test-OptiKitProtectedProcess -Name $process.ProcessName) {
        throw ("O processo '{0}' é protegido e não pode ser suspenso." -f $process.ProcessName)
    }
    if ($process.MainWindowHandle -eq 0) {
        throw ("O processo '{0}' não possui janela e não pode ser suspenso." -f $process.ProcessName)
    }

    Initialize-OptiKitProcessControl
    $handle = [OptiKit.ProcessControl]::OpenProcess(0x0800 -bor 0x1000, $false, $Id)
    if ($handle -eq [IntPtr]::Zero) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw ("Falha ao abrir '{0}' para suspensão (Win32 {1})." -f $process.ProcessName, $code)
    }

    try {
        $status = [OptiKit.ProcessControl]::NtSuspendProcess($handle)
        if ($status -ne 0) {
            throw ("NtSuspendProcess falhou para '{0}' (NTSTATUS {1})." -f $process.ProcessName, $status)
        }
        $script:OptiKitSuspendedProcesses[$Id] = [string]$process.ProcessName
    }
    finally {
        [void][OptiKit.ProcessControl]::CloseHandle($handle)
    }
}

function Resume-OptiKitProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$Id
    )

    $process = Get-Process -Id $Id -ErrorAction SilentlyContinue
    if (-not $process) {
        $script:OptiKitSuspendedProcesses.Remove($Id)
        return
    }

    Initialize-OptiKitProcessControl
    $handle = [OptiKit.ProcessControl]::OpenProcess(0x0800 -bor 0x1000, $false, $Id)
    if ($handle -eq [IntPtr]::Zero) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw ("Falha ao abrir '{0}' para retomada (Win32 {1})." -f $process.ProcessName, $code)
    }

    try {
        $status = [OptiKit.ProcessControl]::NtResumeProcess($handle)
        if ($status -ne 0) {
            throw ("NtResumeProcess falhou para '{0}' (NTSTATUS {1})." -f $process.ProcessName, $status)
        }
        $script:OptiKitSuspendedProcesses.Remove($Id)
    }
    finally {
        [void][OptiKit.ProcessControl]::CloseHandle($handle)
    }
}

function Resume-OptiKitSuspendedProcesses {
    [CmdletBinding()]
    param()

    $ok = $true
    foreach ($id in @($script:OptiKitSuspendedProcesses.Keys)) {
        try {
            Resume-OptiKitProcess -Id ([int]$id)
        }
        catch {
            $ok = $false
            Write-Verbose ("Falha ao retomar PID {0}: {1}" -f $id, $_.Exception.Message)
            $script:OptiKitSuspendedProcesses.Remove([int]$id)
        }
    }
    return $ok
}
