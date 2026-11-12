[CmdletBinding()]
param(
    [string]$SshTarget = 'root@177.7.57.250',
    [ValidateRange(1, 65535)]
    [int]$SshPort = 22
)

$ErrorActionPreference = 'Stop'

if ($SshTarget -notmatch '^[A-Za-z0-9_.-]+@[A-Za-z0-9.-]+$') {
    throw 'SshTarget must use the user@host form.'
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$releaseId = "$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$archiveName = "twine-$releaseId.tar.gz"
$archivePath = Join-Path ([System.IO.Path]::GetTempPath()) $archiveName
$remoteArchive = "/tmp/$archiveName"
$remoteRoot = '/opt/twineprotein'
$remoteRelease = "$remoteRoot/releases/$releaseId"

foreach ($name in @('tar', 'scp', 'ssh')) {
    if (-not (Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue)) {
        throw "Required executable not found on PATH: $name"
    }
}

try {
    & tar -czf $archivePath `
        -C $projectRoot `
        --exclude=.git `
        Dockerfile .dockerignore site deploy
    if ($LASTEXITCODE -ne 0) {
        throw "tar failed with exit code $LASTEXITCODE."
    }

    & scp -P $SshPort -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=15 `
        $archivePath "${SshTarget}:$remoteArchive"
    if ($LASTEXITCODE -ne 0) {
        throw "scp failed with exit code $LASTEXITCODE."
    }

    $remoteCommand = @"
set -eu
install -d '$remoteRelease'
tar -xzf '$remoteArchive' -C '$remoteRelease'
rm -f '$remoteArchive'
bash '$remoteRelease/deploy/activate-release.sh' '$remoteRelease'
bash '$remoteRelease/deploy/configure-domain.sh'
"@ -replace "`r?`n", '; '

    & ssh -p $SshPort -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=15 `
        $SshTarget $remoteCommand
    if ($LASTEXITCODE -ne 0) {
        throw "Remote deployment failed with exit code $LASTEXITCODE."
    }

    Write-Host "Twine release $releaseId deployed successfully."
}
finally {
    Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
}
