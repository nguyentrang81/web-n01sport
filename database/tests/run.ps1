[CmdletBinding()]
param(
    [string]$DbHost = '127.0.0.1',
    [ValidateRange(1,65535)][int]$Port = 3306,
    [string]$User = 'root',
    [string]$MysqlExe
)
$ErrorActionPreference = 'Stop'
if (-not $MysqlExe) {
    $command = Get-Command mysql.exe -ErrorAction SilentlyContinue
    if ($command) {
        $MysqlExe = $command.Source
    } else {
        $MysqlExe = Join-Path $env:ProgramFiles 'MySQL/MySQL Server 8.0/bin/mysql.exe'
    }
}
if (-not (Test-Path -LiteralPath $MysqlExe -PathType Leaf)) {
    throw 'Cannot find mysql.exe. Pass the installed path with -MysqlExe.'
}

$databaseName = 'n01sport_test_' + [Guid]::NewGuid().ToString('N').Substring(0,10)
$installPath = Join-Path $PSScriptRoot '../install.sql'
$smokePath = Join-Path $PSScriptRoot 'smoke.sql'
$install = [IO.File]::ReadAllText($installPath)
$install = [regex]::Replace($install, '(?m)^(CREATE DATABASE(?: IF NOT EXISTS)? |USE )n01sport_dev\b', {
    param($match)
    return $match.Groups[1].Value + $databaseName
})
if ($install -notmatch ('(?m)^USE '+[regex]::Escape($databaseName)+';')) {
    throw 'Could not isolate the test database name.'
}
$scriptPath = [IO.Path]::Combine([IO.Path]::GetTempPath(), "$databaseName.sql")
try {
    [IO.File]::WriteAllText($scriptPath, $install + [Environment]::NewLine + [IO.File]::ReadAllText($smokePath),
        [Text.UTF8Encoding]::new($false))
    $sourcePath = $scriptPath.Replace('\','/')
    & $MysqlExe "--host=$DbHost" "--port=$Port" "--user=$User" --password --default-character-set=utf8mb4 "--execute=source $sourcePath"
    if ($LASTEXITCODE -ne 0) { throw "MySQL test failed in $databaseName." }
    Write-Host "Test database: $databaseName"
} finally {
    if (Test-Path -LiteralPath $scriptPath -PathType Leaf) {
        Remove-Item -LiteralPath $scriptPath
    }
}
