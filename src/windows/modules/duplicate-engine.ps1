# Localizador de arquivos duplicados por tamanho + fingerprint + SHA-256 completo

function Test-OptiKitSystemPath {
    [CmdletBinding()]
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $blocked = @(
        $env:SystemRoot,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramData,
        $env:LOCALAPPDATA,
        $env:APPDATA,
        (Join-Path $env:SystemDrive '$Recycle.Bin'),
        (Join-Path $env:SystemDrive 'System Volume Information')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($item in $blocked) {
        $root = ([IO.Path]::GetFullPath($item)).TrimEnd('\')
        if ($full -ieq $root -or $full.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return ($full -match '^[A-Za-z]:$')
}

function Get-OptiKitFileSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::OpenRead($Path)
        try {
            $hash = $hasher.ComputeHash($stream)
            return ([BitConverter]::ToString($hash) -replace '-', '')
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $hasher.Dispose()
    }
}

function Get-OptiKitFileFingerprint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int64]$Length
    )

    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::OpenRead($Path)
        try {
            [void]$hasher.TransformBlock([Text.Encoding]::UTF8.GetBytes("$Length|"), 0, [Text.Encoding]::UTF8.GetByteCount("$Length|"), $null, 0)
            $buffer = New-Object byte[] 65536
            if ($Length -le 131072) {
                while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    [void]$hasher.TransformBlock($buffer, 0, $read, $null, 0)
                }
            }
            else {
                $first = $stream.Read($buffer, 0, $buffer.Length)
                if ($first -gt 0) { [void]$hasher.TransformBlock($buffer, 0, $first, $null, 0) }
                [void]$stream.Seek(-$buffer.Length, [IO.SeekOrigin]::End)
                $last = $stream.Read($buffer, 0, $buffer.Length)
                if ($last -gt 0) { [void]$hasher.TransformBlock($buffer, 0, $last, $null, 0) }
            }
            [void]$hasher.TransformFinalBlock([byte[]]@(), 0, 0)
            return ([BitConverter]::ToString($hasher.Hash) -replace '-', '')
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $hasher.Dispose()
    }
}

function Find-OptiKitDuplicateFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int64]$MinimumSizeBytes = 1MB
    )

    if (Test-OptiKitSystemPath -Path $Path) {
        throw 'Escolha uma pasta de dados, não uma pasta de sistema.'
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw ("Pasta não encontrada: {0}" -f $Path)
    }

    $files = New-Object 'System.Collections.Generic.List[object]'
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($Path)
    $checked = 0
    while ($stack.Count -gt 0) {
        if ($script:OptiKit -and $script:OptiKit.SyncHash -and $script:OptiKit.SyncHash.CancelRequest) {
            throw 'Escaneamento cancelado.'
        }

        $dir = $stack.Pop()
        try {
            foreach ($entry in @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)) {
                if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                if ($entry.PSIsContainer) {
                    if (-not (Test-OptiKitSystemPath -Path $entry.FullName)) {
                        $stack.Push($entry.FullName)
                    }
                    continue
                }
                if ($entry.Length -lt $MinimumSizeBytes) { continue }
                [void]$files.Add([pscustomobject]@{
                    Path          = $entry.FullName
                    Length        = [int64]$entry.Length
                    LastWriteTime = $entry.LastWriteTime
                })
                $checked++
                if (($checked % 100) -eq 0 -and $script:OptiKit -and $script:OptiKit.SyncHash) {
                    $script:OptiKit.SyncHash.StatusText = ("Escaneando duplicados: {0} arquivos..." -f $checked)
                }
            }
        }
        catch {
            Write-Verbose ("Falha ao enumerar {0}: {1}" -f $dir, $_.Exception.Message)
        }
    }

    $groups = New-Object 'System.Collections.Generic.List[object]'
    foreach ($bySize in @($files | Group-Object -Property Length | Where-Object Count -gt 1)) {
        $fingerprints = New-Object 'System.Collections.Generic.List[object]'
        foreach ($file in @($bySize.Group)) {
            try {
                [void]$fingerprints.Add([pscustomobject]@{
                    File        = $file
                    Fingerprint = (Get-OptiKitFileFingerprint -Path $file.Path -Length $file.Length)
                })
            }
            catch {
                Write-Verbose ("Arquivo inacessível ignorado: {0}" -f $file.Path)
            }
        }

        foreach ($candidate in @($fingerprints | Group-Object -Property Fingerprint | Where-Object Count -gt 1)) {
            $fullHashes = New-Object 'System.Collections.Generic.List[object]'
            foreach ($item in @($candidate.Group)) {
                try {
                    $hash = Get-OptiKitFileSha256 -Path $item.File.Path
                    [void]$fullHashes.Add([pscustomobject]@{ File = $item.File; Hash = $hash })
                }
                catch {
                    Write-Verbose ("Arquivo inacessível ignorado: {0}" -f $item.File.Path)
                }
            }

            foreach ($hashGroup in @($fullHashes | Group-Object -Property Hash | Where-Object Count -gt 1)) {
                $same = @($hashGroup.Group | ForEach-Object { $_.File })
                if ($same.Count -lt 2) { continue }
                [void]$groups.Add([pscustomobject]@{
                    GroupId = [string]$hashGroup.Name
                    Hash    = [string]$hashGroup.Name
                    Length  = [int64]$same[0].Length
                    Files   = @($same | ForEach-Object {
                        [pscustomobject]@{
                            Path          = $_.Path
                            Length        = $_.Length
                            LastWriteTime = $_.LastWriteTime
                        }
                    })
                })
            }
        }
    }

    return @($groups | Sort-Object -Property @{ Expression = { $_.Length * ($_.Files.Count - 1) }; Descending = $true })
}

function Test-OptiKitDuplicateSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Rows
    )

    foreach ($group in @($Rows | Group-Object -Property GroupId)) {
        $selected = @($group.Group | Where-Object { [bool]$_.Delete })
        if ($selected.Count -eq $group.Count) {
            throw 'Mantenha pelo menos um arquivo de cada grupo.'
        }
    }
    return $true
}

function Remove-OptiKitDuplicateFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    Add-Type -AssemblyName Microsoft.VisualBasic
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
        $Path,
        [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
        [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
    )
}
