# Testes do localizador de duplicados: fingerprint, agrupamento e proteção

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'src\windows\modules\duplicate-engine.ps1')

    $script:DuplicateRoot = Join-Path $env:PUBLIC ("optikit_duplicates_" + [Guid]::NewGuid().ToString('N'))
    New-Item -Path $script:DuplicateRoot -ItemType Directory -Force | Out-Null

    $bytes = New-Object byte[] (1MB)
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $rng.Dispose()

    $script:FileA = Join-Path $script:DuplicateRoot 'a.bin'
    $script:FileB = Join-Path $script:DuplicateRoot 'b.bin'
    $script:FileC = Join-Path $script:DuplicateRoot 'c.bin'
    [IO.File]::WriteAllBytes($script:FileA, $bytes)
    [IO.File]::Copy($script:FileA, $script:FileB)

    $other = New-Object byte[] (1MB)
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($other)
    $rng.Dispose()
    [IO.File]::WriteAllBytes($script:FileC, $other)
}

AfterAll {
    if ($script:DuplicateRoot -and (Test-Path -LiteralPath $script:DuplicateRoot)) {
        Remove-Item -LiteralPath $script:DuplicateRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Duplicate Engine (duplicate-engine.ps1)' {
    It 'Deve gerar o mesmo fingerprint para arquivos idênticos e diferente para conteúdo diferente' {
        $length = (Get-Item -LiteralPath $script:FileA).Length
        $a = Get-OptiKitFileFingerprint -Path $script:FileA -Length $length
        $b = Get-OptiKitFileFingerprint -Path $script:FileB -Length $length
        $c = Get-OptiKitFileFingerprint -Path $script:FileC -Length $length

        $a | Should -Be $b
        $a | Should -Not -Be $c
    }

    It 'Deve encontrar somente o par idêntico' {
        $groups = @(Find-OptiKitDuplicateFiles -Path $script:DuplicateRoot -MinimumSizeBytes 1KB)
        $groups.Count | Should -Be 1
        $groups[0].Files.Count | Should -Be 2
        @($groups[0].Files | ForEach-Object Path) | Should -Contain $script:FileA
        @($groups[0].Files | ForEach-Object Path) | Should -Contain $script:FileB
        @($groups[0].Files | ForEach-Object Path) | Should -Not -Contain $script:FileC
    }

    It 'Deve bloquear a seleção de todas as cópias de um grupo' {
        $rows = @(
            [pscustomobject]@{ GroupId = 'g1'; Delete = $true; File = 'a' },
            [pscustomobject]@{ GroupId = 'g1'; Delete = $false; File = 'b' }
        )
        (Test-OptiKitDuplicateSelection -Rows $rows) | Should -BeTrue

        $rows[1].Delete = $true
        { Test-OptiKitDuplicateSelection -Rows $rows } | Should -Throw '*pelo menos um*'
    }

    It 'Deve recusar pastas de sistema como raiz' {
        (Test-OptiKitSystemPath -Path $env:LOCALAPPDATA) | Should -BeTrue
        (Test-OptiKitSystemPath -Path $script:DuplicateRoot) | Should -BeFalse
    }
}
