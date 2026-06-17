# acc bootstrap for Windows -- the one-line entry point. Fetches the repo, then hands
# off to the real installer (install.ps1, the same deterministic phase-machine). This
# script contains ZERO install logic of its own: resolve source -> clone/update -> run.
#
#   irm https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install.ps1 | iex
#
# Invoked via iex there are no positional args -- the installer runs with its defaults.
# To pass installer flags (-DryRun, -Json, a db path), download this file and run it
# directly: .\install.ps1 -DryRun -Json   (everything passes through).
#
# Env: ACC_REPO         git URL to fetch   (default: https://github.com/maxbaluev/accreted-intelligence.git)
#      ACC_SRC          checkout directory (default: $env:LOCALAPPDATA\acc\src)
#      ACC_INSTALL_REF  optional local attribution label passed to install.ps1; written locally, not sent by bootstrap
#      ACC_INSTALL_SOURCE optional coarse source/ref context passed through with the label
#
# PowerShell 5.1+. ASCII-only, like the installer it hands off to. No StrictMode here
# on purpose: iex invocation has no $MyInvocation path and no $args, and the probes
# below must read as $null instead of throwing.

$ErrorActionPreference = 'Stop'

# Direct-file invocation has a script path (and carries $args); iex invocation has neither.
$ScriptPath = $MyInvocation.MyCommand.Path
$AsFile = -not [string]::IsNullOrEmpty($ScriptPath)

$RepoUrl = if ($env:ACC_REPO) { $env:ACC_REPO } else { 'https://github.com/maxbaluev/accreted-intelligence.git' }
$Dest    = if ($env:ACC_SRC)  { $env:ACC_SRC }  else { Join-Path $env:LOCALAPPDATA 'acc\src' }

if ($env:ACC_INSTALL_REF -or $env:ACC_INSTALL_SOURCE) {
  Write-Host 'acc bootstrap: install attribution env set (local receipt only; installer does not send it)'
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw 'acc bootstrap: git not found -- install git first (winget install Git.Git), then re-run.'
}

if (Test-Path (Join-Path $Dest '.git')) {
  Write-Host "acc bootstrap: updating existing checkout at $Dest"
  git -C $Dest pull --ff-only
  if ($LASTEXITCODE -ne 0) {
    Write-Host "acc bootstrap: pull failed (local changes or diverged history) -- continuing with the existing checkout at $Dest"
  }
} else {
  Write-Host "acc bootstrap: cloning $RepoUrl -> $Dest"
  $Parent = Split-Path -Parent $Dest
  if ($Parent -and -not (Test-Path $Parent)) {
    New-Item -ItemType Directory -Force -Path $Parent | Out-Null
  }
  git clone --depth 1 $RepoUrl $Dest
  if ($LASTEXITCODE -ne 0) {
    throw "acc bootstrap: git clone failed ($RepoUrl -> $Dest)"
  }
}

# Prebuilt-availability gate (the public release repo ships binaries + installer + docs only,
# NO engine source). With no Cargo.toml the SOURCE build in install.ps1 cannot work -- but the
# PREBUILT-fetch lane can: install.ps1 resolves the version from the latest release tag and
# downloads + sha256-verifies the prebuilt (acc-v<ver>-x86_64-pc-windows-msvc.zip). So DON'T
# abort on Windows when a prebuilt exists -- hand off and let install.ps1 fetch/verify (with
# its own source fallback). Abort ONLY when there is genuinely no prebuilt target (e.g. a
# cross-platform pwsh host on macOS where the macOS prebuilt is still pending).
if (-not (Test-Path (Join-Path $Dest 'Cargo.toml'))) {
  $Releases = 'https://github.com/maxbaluev/accreted-intelligence/releases'
  $IsMac = $false
  try { $IsMac = [bool](Get-Variable -Name 'IsMacOS' -ValueOnly -ErrorAction SilentlyContinue) } catch { $IsMac = $false }
  if ($IsMac) {
    throw "acc bootstrap: no engine source in $Dest (public release repo) and the macOS prebuilt is coming soon -- track $Releases"
  }
  # Windows: the x86_64-pc-windows-msvc prebuilt is published -- hand off to install.ps1.
  Write-Host "acc bootstrap: no engine source in $Dest (public release repo) -- handing off for the prebuilt x86_64-pc-windows-msvc binary (install.ps1 resolves the latest release tag, fetches + sha256-verifies)"
}

$Installer = Join-Path $Dest 'install.ps1'
Write-Host "acc bootstrap: handing off to $Installer"
Push-Location $Dest
try {
  if ($AsFile) { & $Installer @args } else { & $Installer }
} finally {
  Pop-Location
}
if ($AsFile) { exit $LASTEXITCODE }
