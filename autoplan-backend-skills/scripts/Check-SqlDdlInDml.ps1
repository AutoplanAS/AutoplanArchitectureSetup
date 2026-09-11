# Detects DDL column definitions (type declarations) that have been pasted into a DML
# statement -- typically into a MERGE's UPDATE SET or INSERT list. C# compiles these
# happily because they live inside a string literal; SQL Server rejects them at runtime.
#
# Usage:
#   .\Check-SqlDdlInDml.ps1 -Path <file-or-directory>

param(
    [Parameter(Mandatory = $true)][string]$Path
)

$sqlTypes = 'NVARCHAR|VARCHAR|DECIMAL|NUMERIC|BIGINT|SMALLINT|TINYINT|INT|BIT|DATETIMEOFFSET|DATETIME2|DATETIME|UNIQUEIDENTIFIER|FLOAT|REAL|MONEY'

$files = if (Test-Path -LiteralPath $Path -PathType Container) {
    Get-ChildItem -LiteralPath $Path -Recurse -Filter *.cs -File |
        Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' }
} else {
    Get-Item -LiteralPath $Path
}

$findings = @()

foreach ($file in $files) {
    $lines = Get-Content -LiteralPath $file.FullName
    $inDml = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        # Enter DML context on a MERGE/UPDATE/INSERT; leave it on a CREATE/ALTER TABLE.
        if ($line -match '\b(MERGE\s+INTO|UPDATE\s+SET|WHEN\s+MATCHED)\b') { $inDml = $true }
        if ($line -match '\b(CREATE\s+TABLE|ALTER\s+TABLE|CREATE\s+INDEX)\b') { $inDml = $false }
        if ($line -match '";\s*$') { $inDml = $false }

        # A DDL column definition is "Name TYPE" with no assignment on the line.
        if ($inDml -and $line -match "\b[A-Za-z_][A-Za-z0-9_]*\s+($sqlTypes)\b" -and $line -notmatch '=') {
            $findings += [pscustomobject]@{
                File = $file.FullName
                Line = $i + 1
                Text = $line.Trim()
            }
        }
    }
}

if ($findings) {
    Write-Output "DDL type declarations found inside DML statements:"
    $findings | ForEach-Object { Write-Output ("  {0}:{1}  {2}" -f $_.File, $_.Line, $_.Text) }
    exit 1
}

Write-Output "No DDL type declarations found inside DML statements."
exit 0
