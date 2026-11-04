# Testes unitários do logger, Invoke-Mutation (DryRun) e persistência atômica do backup/state.json

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'src\windows\core\logger.ps1')
    . (Join-Path $script:RepoRoot 'src\windows\core\backup.ps1')
}

Describe 'Logger e Ponto Único de Mutação (logger.ps1)' {
    BeforeEach {
        $testRoot = Join-Path $TestDrive ("optikit_" + [Guid]::NewGuid().ToString('N'))
        $sync = @{
            LogQueue   = New-Object 'System.Collections.Concurrent.ConcurrentQueue[psobject]'
            StatusText = ''
        }
        Initialize-OptiKitEnvironment -DataRoot $testRoot -DryRun:$false -SyncHash $sync | Out-Null
    }

    It 'Deve gravar entradas de log em arquivo UTF-8 e enfileirar na ConcurrentQueue da UI' {
        Write-OptimizerLog -Level INFO -Message 'Iniciando verificação de acentuação: Otimização concluída'
        Test-Path -LiteralPath $script:OptiKit.LogFile | Should -BeTrue

        $content = [System.IO.File]::ReadAllText($script:OptiKit.LogFile, [System.Text.Encoding]::UTF8)
        $content | Should -Match 'Otimização concluída'

        $queuedItem = $null
        $deq = $script:OptiKit.SyncHash.LogQueue.TryDequeue([ref]$queuedItem)
        $deq | Should -BeTrue
        $queuedItem.Level | Should -Be 'INFO'
        $queuedItem.Message | Should -Match 'Otimização concluída'
    }

    It 'Invoke-Mutation deve impedir execução real quando DryRun está ativo e registrar [DRYRUN]' {
        Initialize-OptiKitEnvironment -DryRun:$true | Out-Null
        $script:Executed = $false
        Invoke-Mutation -Description 'Alterar chave crítica de teste' -Action {
            $script:Executed = $true
        } | Out-Null

        $script:Executed | Should -BeFalse
        ($script:OptiKit.LogHistory -join "`n") | Should -Match '\[DRYRUN\] Alterar chave crítica de teste'
    }
}

Describe 'Persistência de Estado e Undo Engine (backup.ps1)' {
    BeforeEach {
        $testRoot = Join-Path $TestDrive ("backup_" + [Guid]::NewGuid().ToString('N'))
        Initialize-OptiKitEnvironment -DataRoot $testRoot -DryRun:$false | Out-Null
        New-OptiKitBackupSession -SessionId '2026-11-02_16-00-00' | Out-Null
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

        $snapshotPath = Join-Path $script:OptiKit.SessionDir 'state-snapshot.json'
        Test-Path -LiteralPath $snapshotPath | Should -BeTrue

        Remove-CapturedState -Id 'WPFTweaksMouseRawInput'
        (Get-CapturedState -Id 'WPFTweaksMouseRawInput') | Should -BeNullOrEmpty
    }

    It 'Deve colocar em quarentena um state.json corrompido e retornar estado vazio' {
        $corruptPath = Join-Path $TestDrive ("corrupt_" + [Guid]::NewGuid().ToString('N') + '.json')
        $corruptContent = '{ "broken": '
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($corruptPath, $corruptContent, $utf8Bom)

        $state = Read-OptiKitStateFile -StateFilePath $corruptPath

        $state.Count | Should -Be 0
        Test-Path -LiteralPath $corruptPath | Should -BeFalse

        $corruptLeaf = Split-Path -Path $corruptPath -Leaf
        $quarantined = @(Get-ChildItem -LiteralPath $TestDrive -Filter ("{0}.corrupt-*" -f $corruptLeaf) -File)
        $quarantined.Count | Should -Be 1
        ([System.IO.File]::ReadAllText($quarantined[0].FullName, [System.Text.Encoding]::UTF8)) | Should -Be $corruptContent
    }

    It 'Deve sobrescrever o state.json atomicamente, sem deixar arquivos temporários' {
        $statePath = Join-Path $TestDrive ("atomic_" + [Guid]::NewGuid().ToString('N') + '.json')

        Write-OptiKitStateFile -StateFilePath $statePath -StateData @{ marker = 'primeiro'; count = 1 }
        Write-OptiKitStateFile -StateFilePath $statePath -StateData @{ marker = 'segundo'; count = 2 }

        $parsed = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $parsed.marker | Should -Be 'segundo'
        $parsed.count | Should -Be 2

        @(Get-ChildItem -LiteralPath $TestDrive -Filter '*.tmp' -File).Count | Should -Be 0
    }
}
