# Testes unitários do logger, Invoke-Mutation (DryRun) e persistência atômica do backup/state.json

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'src\windows\core\logger.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\core\backup.ps1')
}

Describe 'Logger e Ponto Único de Mutação (logger.ps1)' {
    BeforeEach {
        $testRoot = Join-Path $TestDrive ("redimo_" + [Guid]::NewGuid().ToString('N'))
        $sync = @{
            LogQueue   = New-Object 'System.Collections.Concurrent.ConcurrentQueue[psobject]'
            StatusText = ''
        }
        Initialize-RedimoEnvironment -DataRoot $testRoot -DryRun:$false -SyncHash $sync | Out-Null
    }

    It 'Deve gravar entradas de log em arquivo UTF-8 e enfileirar na ConcurrentQueue da UI' {
        Write-OptimizerLog -Level INFO -Message 'Iniciando verificação de acentuação: Otimização concluída'
        Test-Path -LiteralPath $script:Redimo.LogFile | Should -BeTrue

        $content = [System.IO.File]::ReadAllText($script:Redimo.LogFile, [System.Text.Encoding]::UTF8)
        $content | Should -Match 'Otimização concluída'

        $queuedItem = $null
        $deq = $script:Redimo.SyncHash.LogQueue.TryDequeue([ref]$queuedItem)
        $deq | Should -BeTrue
        $queuedItem.Level | Should -Be 'INFO'
        $queuedItem.Message | Should -Match 'Otimização concluída'
    }

    It 'Invoke-Mutation deve impedir execução real quando DryRun está ativo e registrar [DRYRUN]' {
        Initialize-RedimoEnvironment -DryRun:$true | Out-Null
        $script:Executed = $false
        Invoke-Mutation -Description 'Alterar chave crítica de teste' -Action {
            $script:Executed = $true
        } | Out-Null

        $script:Executed | Should -BeFalse
        ($script:Redimo.LogHistory -join "`n") | Should -Match '\[DRYRUN\] Alterar chave crítica de teste'
    }
}

Describe 'Persistência de Estado e Undo Engine (backup.ps1)' {
    BeforeEach {
        $testRoot = Join-Path $TestDrive ("backup_" + [Guid]::NewGuid().ToString('N'))
        Initialize-RedimoEnvironment -DataRoot $testRoot -DryRun:$false | Out-Null
        New-RedimoBackupSession -SessionId '2026-11-02_16-00-00' | Out-Null
    }

    It 'Deve converter caminhos de registro do PowerShell para o formato do reg.exe' {
        ConvertTo-RegExePath -PsPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows' | Should -Be 'HKLM\SOFTWARE\Policies\Microsoft\Windows'
        ConvertTo-RegExePath -PsPath 'HKCU:\Control Panel\Mouse' | Should -Be 'HKCU\Control Panel\Mouse'
    }

    It 'Deve respeitar a regra First-Capture-Wins (idempotência) e remover após Undo' {
        $initialCapture = @(
            @{ kind = 'registry'; path = 'HKCU:\Control Panel\Mouse'; name = 'MouseSpeed'; existed = $true; type = 'String'; value = '1' }
        )
        $secondCapture = @(
            @{ kind = 'registry'; path = 'HKCU:\Control Panel\Mouse'; name = 'MouseSpeed'; existed = $true; type = 'String'; value = '0' }
        )

        Save-CapturedState -Id 'WPFTweaksMouseRawInput' -CapturedItems $initialCapture
        Save-CapturedState -Id 'WPFTweaksMouseRawInput' -CapturedItems $secondCapture

        $saved = Get-CapturedState -Id 'WPFTweaksMouseRawInput'
        $null -ne $saved | Should -BeTrue
        $saved.captured[0].value | Should -Be '1'

        $snapshotPath = Join-Path $script:Redimo.SessionDir 'state-snapshot.json'
        Test-Path -LiteralPath $snapshotPath | Should -BeTrue

        Remove-CapturedState -Id 'WPFTweaksMouseRawInput'
        (Get-CapturedState -Id 'WPFTweaksMouseRawInput') | Should -BeNullOrEmpty
    }
}
