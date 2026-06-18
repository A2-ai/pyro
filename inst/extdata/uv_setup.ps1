# uv_setup.ps1 <VenvDirectory> <TomlDirectory> <UvVersion> [-Groups <a>,<b>,...]
#
# Ensures uv is installed at $UvVersion, runs `uv lock` to refresh the
# lockfile against $TomlDirectory\pyproject.toml (no-op when already in
# sync), then runs `uv sync --frozen` to materialize the venv at
# $VenvDirectory\.venv. $TomlDirectory is the project root containing
# the pyproject.toml + uv.lock pair that uv resolves against — under
# pyro's project-root model this is the user's project, seeded
# from the bundled spec on first init.
#
# When -Groups is empty, runs:
#   uv sync --frozen --all-groups
# When -Groups contains one or more names, runs:
#   uv sync --frozen --inexact --group <g1> --group <g2> ...
# `--inexact` keeps packages from previously installed groups in place,
# so sibling fyr-packages can each install their own group additively
# without removing each other's deps.

param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VenvDirectory,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TomlDirectory,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+(-[\w\.]+)?$')]
    [string]$UvVersion,

    [Parameter(Mandatory = $false)]
    [string[]]$Groups = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $TomlDirectory -PathType Container)) {
    throw "toml_dir '$TomlDirectory' does not exist"
}

# Default SecurityProtocol on older Win10 / PS 5.1 is SSL3/TLS 1.0;
# astral.sh rejects, or a downgrading proxy can serve garbage.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Ensure ~/.local/bin is on PATH — entry-wise compare so substrings like
# '.local\binaries' can't false-match '.local\bin'.
$LocalBin = Join-Path $env:USERPROFILE '.local\bin'
$PathParts = $env:PATH -split ';'
if ($PathParts -notcontains $LocalBin) {
    $env:PATH = "$LocalBin;$env:PATH"
}

function Install-Uv {
    param([string]$Version)

    $InstallUrl = "https://astral.sh/uv/$Version/install.ps1"
    $InstallerScript = Invoke-RestMethod -Uri $InstallUrl
    Invoke-Expression $InstallerScript
    if ($LASTEXITCODE -ne 0) {
        throw "uv installer exited with code $LASTEXITCODE"
    }

    # Merge fresh registry PATH onto the existing session PATH rather than
    # overwrite (prior session additions like $LocalBin must survive).
    $RegPath = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') +
               ';' +
               [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    $env:PATH = "$env:PATH;$RegPath"
}

$uvCmd = Get-Command uv -ErrorAction SilentlyContinue
if (-not $uvCmd) {
    Write-Host "uv not installed; installing $UvVersion..."
    Install-Uv -Version $UvVersion
} else {
    # 'uv 0.10.11 (hash date)' -> second whitespace-separated token.
    # Split-based extraction handles pre-release suffixes like '0.7.8-rc.1'
    # that a \d+\.\d+\.\d+ regex would silently truncate.
    $installedRaw = (& uv --version) 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "uv --version failed with exit $LASTEXITCODE"
    }
    $installedVer = ($installedRaw -split '\s+')[1]
    if ($installedVer -ne $UvVersion) {
        Write-Host "uv $installedVer != required $UvVersion; installing $UvVersion..."
        Install-Uv -Version $UvVersion
    } else {
        Write-Host "Using existing uv $installedVer."
    }
}

$env:UV_PROJECT_ENVIRONMENT = Join-Path $VenvDirectory '.venv'

# Refresh the lock to match the toml. uv lock is a no-op when the lock
# is already up-to-date; if the user edited pyproject.toml or pyro
# (or a sibling wrapper) just spliced in a new group, this regenerates.
& uv lock --project $TomlDirectory
if ($LASTEXITCODE -ne 0) {
    throw "uv lock failed with exit $LASTEXITCODE"
}

if ($Groups.Count -eq 0) {
    & uv sync --project $TomlDirectory --frozen --all-groups
} else {
    $GroupArgs = @()
    foreach ($g in $Groups) {
        $GroupArgs += '--group'
        $GroupArgs += $g
    }
    & uv sync --project $TomlDirectory --frozen --inexact @GroupArgs
}
if ($LASTEXITCODE -ne 0) {
    throw "uv sync failed with exit $LASTEXITCODE"
}

Write-Host "Python environment ready at $($env:UV_PROJECT_ENVIRONMENT)"
