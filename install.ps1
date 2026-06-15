<#
.SYNOPSIS
acc installer for native Windows -- deterministic PHASE-MACHINE.

.DESCRIPTION
Mirrors install.sh's semantics exactly: numbered, idempotent, individually re-runnable
phases; resume is structural (each phase checks its own postcondition first -- no state
file). Drives the WINDOWS tier ladder from probed host facts (nvidia-smi free VRAM, OS
build, PROCESSOR_ARCHITECTURE, total RAM), so the embedder lane is chosen, not guessed.

WINDOWS TIER LADDER (full bf16 only -- AWQ/triton has NO windows wheels, never selected;
mirrors src/selector.rs select_model_for_os windows branch so phase 0 and `acc pin` AGREE):
  NVIDIA, free VRAM >= 20GB  -> ColQwen3-8B full bf16 on cuda (torch-cuda resolves natively)
  NVIDIA, free VRAM >= 12GB  -> ColQwen3-4B full bf16 on cuda
  NVIDIA, free VRAM >= 2GB   -> LateOn text-only ON cuda (small ~0.6GB model fits a ~4GB GPU --
                               runs on the GPU instead of a 10-100x slower cpu encode)
  no usable GPU, RAM >= 2GB  -> LateOn text-only on cpu (light ~0.6GB default; multimodal needs
                               a cuda GPU, or force ACC_TIER=8b-full/4b-full to run it on cpu)
  below                      -> the CONTAINER tier path (docs/INSTALL_CONTAINER.md)
  DISK FLOOR (every rung): expected model download (static sizes mirrored from
  encoders/prefetch.py) + 2048MB headroom must fit the free disk at the HF cache
  (HF_HOME, default %USERPROFILE%\.cache\huggingface; probed via PSDrive), else the
  pick degrades one rung at a time (8b -> 4b -> lateon) with the honest
  'disk floor: need ~XGB, have ~YGB' reason -- same honesty as the VRAM floors.
Override with ACC_TIER=<8b-full|4b-full|lateon|container>. The four AWQ lanes
(8b-awq|4b-awq|8b-cpu|4b-cpu) are refused on windows (no triton wheels) -> host probe.

MODEL PREFETCH (phase 6, model_prefetch): downloads the pinned model into the HF
cache with VISIBLE progress (uv run encoders\prefetch.py -- snapshot_download's
native resume + cache reuse; idempotent, a cache hit is instant) BEFORE the daemon
phase, instead of hiding an up-to-8.3GB download inside the daemon warm-up. A
network failure skips the phase -- the daemon still downloads lazily on first start
(prefetch is UX, not a new dependency).

ENV KNOBS (mirrors install.sh's Env section):
  ACC_NONINTERACTIVE=1  never prompt (same as -NonInteractive)
  ACC_NO_BROWSER=1      skip the browser capability
  ACC_TIER=<lane>       force the embedder lane (skip the host probe's pick)
  ACC_INSTALL=source    skip the phase-3 prebuilt-release fetch; always build from source

ENGINE LANE HONESTY: the acc windows engine port is IN FLIGHT. Phase 3 first tries the
PREBUILT release lane (sha256-verified download of acc.exe -- no VS Build Tools needed
when a release is reachable; ACC_INSTALL=source opts out) and only then falls back to
the source build. Phases that need the
built binary or the live daemon (model_pin, substrate init, embedder_daemon, seed,
verify) detect-and-report honestly with explicit "engine windows lane pending" notes
instead of faking success. probe/deps/build/config/wiring phases are fully functional
NOW. Unlike install.sh (which exits 1 on a build failure), a failed build here marks
the phase failed and CONTINUES so config + Claude Code wiring still land; the final
exit code is still non-zero. That is the one deliberate deviation, for the in-flight
port.

Windows-specific reality this installer owns:
  - config home:  %APPDATA%\acc   (auth store -- matches src/brain.rs default_auth_path;
                                    model pin lands here under the engine port contract)
  - cache home:   %LOCALAPPDATA%\acc
  - daemon endpoint: TCP-loopback + token (NO unix sockets on native windows). The
    daemon publishes %LOCALAPPDATA%\acc\run\embedder.port + embedder.token; clients
    connect 127.0.0.1:<port> and authenticate with the token. This installer writes
    run\endpoint.json declaring that contract (engine_lane: pending|live).
  - sandbox: no bwrap on windows -- exec runtimes run under acc's built-in deadline.
  - browser: Camoufox host-side lane -- browser venv under %APPDATA%\acc\browser,
    endpoint via the same TCP-loopback + token local-IPC contract as the Rust client.
  - sqlite: rusqlite uses the bundled amalgamation on windows (Cargo.toml target block)
    -- no system sqlite dev package needed.

.PARAMETER DbPath
Substrate db path (default: <repo>\acc.db). Never clobbered if it exists.

.PARAMETER DryRun
Walk every phase, mutate NOTHING, report what WOULD happen (the self-test).
Cross-platform: also runs under pwsh on linux/mac as a parse/contract self-test.

.PARAMETER Json
One JSON object per phase {phase,status,detail,next}; final line = overall verdict +
the `acc doctor --json` handoff (Claude-as-installer). Human chatter goes to stderr.

.PARAMETER NonInteractive
Never prompt (also honored via ACC_NONINTERACTIVE=1). This installer is deterministic
and prompt-free by design (mirrors install.sh's AUTO-INSTALL stance); the flag is the
structural guarantee any future interactive step must honor.

.EXAMPLE
.\install.ps1 -DryRun -Json
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)] [string]$DbPath,
  [switch]$DryRun,
  [switch]$Json,
  [switch]$NonInteractive,
  [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Help) { Get-Help -Detailed $MyInvocation.MyCommand.Path; exit 0 }

# -- environment ------------------------------------------------------------------------
$script:OnWindows = $true
if ($PSVersionTable.PSVersion.Major -ge 6) { $script:OnWindows = $IsWindows }

$Repo = $PSScriptRoot
Set-Location $Repo
# $DbPath default is set AFTER $ConfigHome is computed below: a RELEASE install (non-git)
# must write the db to the per-OS CANONICAL DATA DIR (%APPDATA%\acc\acc.db) -- the SAME path
# `db::canonical_db_path` now resolves a bare `acc.db` to outside a git repo. Otherwise bare
# `acc report`/`acc doctor` (read-only, cannot create) look in the canonical dir while the
# installer wrote the db under $Repo -- the exact split that hard-FAILED for a real user.

$NonInteractive = $NonInteractive -or ($env:ACC_NONINTERACTIVE -eq '1')
$NoBrowser = ($env:ACC_NO_BROWSER -eq '1')

# NON-INTERACTIVE also covers a redirected/captured stdout (an agent's shell pipes our output
# and enforces a command TIMEOUT) -- in that mode the embedder warm-wait below must NOT block,
# or the agent kills the install mid-wait and never sees the next-step guidance. Mirrors
# install.sh's `! [ -t 1 ]`. Write-Host -ForegroundColor already strips its colors when
# redirected, so no extra ANSI guard is needed on the PowerShell side.
$OutputRedirected = $false
try { $OutputRedirected = [Console]::IsOutputRedirected } catch { $OutputRedirected = $false }
$NonInteractive = $NonInteractive -or $OutputRedirected

# Windows config/cache homes (the engine port contract). On a non-windows dry-run host,
# GetFolderPath maps to the XDG equivalents -- reported, never mutated.
function Get-WinAppData {
  if ($env:APPDATA) { return $env:APPDATA }
  return [Environment]::GetFolderPath('ApplicationData')
}
function Get-WinLocalAppData {
  if ($env:LOCALAPPDATA) { return $env:LOCALAPPDATA }
  return [Environment]::GetFolderPath('LocalApplicationData')
}
$ConfigHome     = Join-Path (Get-WinAppData) 'acc'        # auth.json + model.json (src/brain.rs contract)
# The substrate db lives in the CANONICAL DATA DIR ($ConfigHome = %APPDATA%\acc), matching
# `crate::platform::data_dir().join("acc.db")` -- the exact path `db::canonical_db_path`
# resolves a bare `acc.db` to for a non-git release install. So the installer, the wired MCP
# (relative `acc.db` -> same canonical dir off-git), and bare read-only `acc` commands all
# agree on ONE db. An explicit -DbPath argument still wins (absolute paths pass through).
if (-not $DbPath) { $DbPath = Join-Path $ConfigHome 'acc.db' }
$CacheHome      = Join-Path (Get-WinLocalAppData) 'acc'   # caches
$RunDir         = Join-Path $CacheHome 'run'               # daemon endpoint home
$EmbPortFile    = Join-Path $RunDir 'embedder.port'
$EmbTokenFile   = Join-Path $RunDir 'embedder.token'
$EndpointConfig = Join-Path $RunDir 'endpoint.json'
$EmbLogOut      = Join-Path $RunDir 'embedder.log'
$EmbLogErr      = Join-Path $RunDir 'embedder.err.log'
$BrowserHome    = if ($env:ACC_BROWSER_HOME) { $env:ACC_BROWSER_HOME } else { Join-Path $ConfigHome 'browser' }
$BrowserVenv    = Join-Path $BrowserHome 'venv'
$BrowserScripts = Join-Path $BrowserVenv 'Scripts'
$BrowserPython  = Join-Path $BrowserScripts 'python.exe'
$BrowserProfiles = Join-Path $BrowserHome 'profiles'

$EncoderScript  = Join-Path (Join-Path $Repo 'encoders') 'li_encode.py'   # the ONE windows lane (PEP508 markers resolve torch per platform)

# RepoIsClone -- is $Repo the HIDDEN bootstrap clone ($env:LOCALAPPDATA\acc\src, the dir the
# one-liner clones into and runs from), rather than a project the user opens? The bootstrap
# clones to $env:ACC_SRC (default $env:LOCALAPPDATA\acc\src) and runs this script from there,
# so $Repo == that path on the public one-liner path. When $Repo is the clone we must NOT wire
# Claude Code PROJECT files (.mcp.json / .claude\settings.json) into it -- the user never opens
# Claude Code in the clone, so that wiring is dead. The one-Work-Model pivot makes those project
# files unnecessary anyway: phase 14 (`acc hosts-sync`) wires Claude Code GLOBALLY (~/.claude.json
# + ~/.claude/settings.json on the one global db), so acc works in every directory. A real dev
# clone the user works in is NOT under LocalAppData, so this stays $false there. Mirrors
# install.sh's REPO_IS_CLONE.
$CloneDir = if ($env:ACC_SRC) { $env:ACC_SRC } else { Join-Path (Get-WinLocalAppData) 'acc\src' }
$RepoIsClone = $false
try {
  $rp = (Resolve-Path -LiteralPath $Repo -ErrorAction SilentlyContinue).Path
  $cp = (Resolve-Path -LiteralPath $CloneDir -ErrorAction SilentlyContinue).Path
  if ($rp -and $cp) { $RepoIsClone = ($rp.TrimEnd('\','/') -ieq $cp.TrimEnd('\','/')) }
  elseif ($Repo) { $RepoIsClone = ($Repo.TrimEnd('\','/') -ieq $CloneDir.TrimEnd('\','/')) }
} catch { $RepoIsClone = $false }

$EnginePendingNote = 'engine windows lane pending -- the acc windows engine port is in flight (src embedder/daemon lanes); this phase activates once cargo build --release succeeds on windows'

# -- output surface ----------------------------------------------------------------------
# Human mode -> pretty lines. JSON mode -> exactly one object per phase on STDOUT;
# everything else goes to stderr (mirror of install.sh's log/ok/warn/step).
function Write-Chatter([string]$Msg) {
  if ($Json) { [Console]::Error.WriteLine($Msg) } else { Write-Host $Msg }
}
function Say([string]$Msg)  { Write-Chatter ('  ' + $Msg) }
function Ok([string]$Msg)   { if ($Json) { [Console]::Error.WriteLine('  + ' + $Msg) } else { Write-Host ('  + ' + $Msg) -ForegroundColor Green } }
function Warn([string]$Msg) { if ($Json) { [Console]::Error.WriteLine('  ! ' + $Msg) } else { Write-Host ('  ! ' + $Msg) -ForegroundColor Yellow } }
function Step([string]$Msg) { Write-Chatter ''; if ($Json) { [Console]::Error.WriteLine('> ' + $Msg) } else { Write-Host ('> ' + $Msg) -ForegroundColor White } }

$script:AnyFailed = $false

# Emit-Phase NAME STATUS DETAIL [NEXT] -- single funnel: pretty line (human) OR json line.
# STATUS in ok|failed|skipped|would. Mirrors install.sh's phase_result/json_phase exactly.
function Emit-Phase([string]$Name, [string]$Status, [string]$Detail, [string]$Next = '') {
  if ($Status -eq 'failed') { $script:AnyFailed = $true }
  if ($Json) {
    $obj = [ordered]@{ phase = $Name; status = $Status; detail = $Detail; next = $null }
    if ($Next) { $obj.next = $Next }
    Write-Output (ConvertTo-Json -InputObject ([pscustomobject]$obj) -Compress)
  } else {
    switch ($Status) {
      'ok'      { Ok $Detail }
      'would'   { Say ('WOULD: ' + $Detail) }
      'skipped' { Say ('skip: ' + $Detail); if ($Next) { Say ('  -> ' + $Next) } }
      'failed'  { Warn $Detail; if ($Next) { Warn ('-> ' + $Next) } }
    }
  }
}

function Have([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# In a real run, mutating actions execute; in -DryRun they are reported, never run.
function Act([string]$Desc, [scriptblock]$Action) {
  if ($DryRun) { Say ('WOULD: ' + $Desc); return $true }
  try { & $Action; return $true }
  catch { Warn ($Desc + ' failed: ' + $_.Exception.Message); return $false }
}

function Install-WingetPackage([string]$Id, [string]$Label, [string[]]$ExtraArgs = @()) {
  if (-not (Have 'winget')) { return $false }
  return (Act ("install $Label via winget ($Id)") {
    $args = @(
      'install', '--id', $Id, '--exact', '--source', 'winget',
      '--silent', '--accept-package-agreements', '--accept-source-agreements'
    )
    if ($ExtraArgs.Count -gt 0) { $args += $ExtraArgs }
    $r = Invoke-Native 'winget' $args
    if (-not $r.ok) { throw "winget install $Id failed" }
  })
}

# Run a native command quietly; never throws; returns @{ ok; out }.
function Invoke-Native([string]$Exe, [string[]]$Argv) {
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    $out = & $Exe @Argv 2>$null
    return @{ ok = ($LASTEXITCODE -eq 0); out = $out }
  } catch { return @{ ok = $false; out = '' } }
  finally { $ErrorActionPreference = $prev }
}

# Run a native command with its output streamed to the chatter surface (build logs).
function Invoke-NativeChatter([string]$Exe, [string[]]$Argv) {
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    & $Exe @Argv 2>&1 | ForEach-Object { Write-Chatter ('    ' + $_) }
    return ($LASTEXITCODE -eq 0)
  } catch { return $false }
  finally { $ErrorActionPreference = $prev }
}

# =========================================================================================
# PHASE 0 -- probe + tier select. Mirrors install.sh phase 0 SHELL-SIDE for windows:
# OS build, arch via PROCESSOR_ARCHITECTURE, nvidia-smi free VRAM, total RAM -- plus the
# DISK FLOOR: free disk at the HF cache (PSDrive) must fit the pick's expected download
# + headroom, else the pick degrades one rung at a time. Pure read --
# runs identically in dry-run and real mode. Guarded so a cross-platform dry-run works.
# =========================================================================================
# Selector floors (MB) -- the WINDOWS ladder (full bf16 lanes only; never AWQ/triton).
# MIRROR src/selector.rs WIN_FULL_{8B,4B}_MIN_VRAM_MB so phase 0 and `acc pin` AGREE (they
# disagreed before: phase 0 used 10/5GB and prefetched an 8B the Rust pin would never select).
$CUDA_8B_VRAM = 20000; $CUDA_4B_VRAM = 12000
$LATEON_RAM   = 2000
# Small-VRAM cuda floor (MB): LateOn (dim-128, ~0.6GB) runs ON cuda when a GPU is present but
# below the full-bf16 floors. MIRROR src/selector.rs LATEON_MIN_VRAM_MB so phase 0 and the Rust
# `acc pin` AGREE -- a ~4GB GPU (the real 3938MiB install) runs the small model on cuda, not cpu.
$LATEON_VRAM  = 2000

# DISK FLOOR (MB) -- model weights land in the HF cache; the pick's expected download
# (static sizes mirrored from encoders/prefetch.py STATIC_EXPECTED_BYTES) + headroom
# must fit the free disk there, else the ladder degrades ONE rung at a time
# (8b -> 4b -> lateon). Same honesty as the VRAM floors: a host with 6GB free disk
# must never select an 8.3GB tier and die mid-download.
$MODEL_MB_8B_FULL = 8300; $MODEL_MB_4B_FULL = 4200   # full bf16 (~8.3GB / ~4.2GB)
$MODEL_MB_LATEON  = 600                              # LateOn text-only (~0.6GB)
$DISK_HEADROOM_MB = 2048

function Get-HfCacheDir {
  # Where snapshot_download lands weights: HF_HOME wins; windows default
  # %USERPROFILE%\.cache\huggingface ($HOME is %USERPROFILE% on native windows).
  if ($env:HF_HOME) { return $env:HF_HOME }
  return Join-Path (Join-Path $HOME '.cache') 'huggingface'
}

function Probe-FreeDiskMb {
  # Free MB on the drive that will hold the HF cache (PSDrive probe). The cache dir
  # may not exist yet on a fresh host -- walk up to the nearest existing ancestor.
  # Returns -1 when the probe fails (floor is then skipped with an explicit note).
  $d = Get-HfCacheDir
  while (-not (Test-Path $d)) {
    $parent = Split-Path $d -Parent
    if (-not $parent -or ($parent -eq $d)) { break }
    $d = $parent
  }
  try {
    $drive = (Get-Item $d -ErrorAction Stop).PSDrive
    if (($null -ne $drive) -and ($null -ne $drive.Free)) { return [int64]($drive.Free / 1MB) }
  } catch { }
  return -1
}

# Get-ExpectedModelMb TIER -- the static expected download for a tier's pinned model (MB).
function Get-ExpectedModelMb([string]$Tier) {
  switch ($Tier) {
    '8b-full' { return $MODEL_MB_8B_FULL }
    '4b-full' { return $MODEL_MB_4B_FULL }
    'lateon'  { return $MODEL_MB_LATEON }
    default   { return 0 }
  }
}

function MbToGb([int64]$Mb) {
  return ([math]::Round($Mb / 1024.0, 1)).ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-OsBuild {
  if ($script:OnWindows -and (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
    try {
      $os = Get-CimInstance Win32_OperatingSystem
      return ($os.Caption.Trim() + ' build ' + $os.BuildNumber)
    } catch { }
  }
  return [System.Runtime.InteropServices.RuntimeInformation]::OSDescription.Trim()
}

function Get-Arch {
  if ($env:PROCESSOR_ARCHITECTURE) { return $env:PROCESSOR_ARCHITECTURE }   # AMD64 | ARM64
  return [string][System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
}

function Read-TotalRamMb {
  if ($script:OnWindows -and (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
    try { return [int]((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB) } catch { return 0 }
  }
  if (Test-Path '/proc/meminfo') {   # cross-platform dry-run self-test lane
    $m = Select-String -Path '/proc/meminfo' -Pattern '^MemTotal:\s+(\d+)' | Select-Object -First 1
    if ($m) { return [int]([int64]$m.Matches[0].Groups[1].Value / 1024) }
  }
  return 0
}

function Probe-VramFreeMb {
  # Free VRAM a FRESH install would see. On an already-installed host the live embedder
  # daemon is HOLDING the GPU (its endpoint files exist) -- reading "free" would lie low
  # and drop the tier; the honest fresh-install figure is then TOTAL VRAM (mirror of
  # install.sh's probe_vram_free_mb socket check, transposed to the port-file contract).
  if (-not (Have 'nvidia-smi')) { return 0 }
  $free = 0; $total = 0
  $rf = Invoke-Native 'nvidia-smi' @('--query-gpu=memory.free', '--format=csv,noheader,nounits')
  $rt = Invoke-Native 'nvidia-smi' @('--query-gpu=memory.total', '--format=csv,noheader,nounits')
  if ($rf.ok -and $rf.out) { try { $free  = [int](('' + ($rf.out | Select-Object -First 1)).Trim()) } catch { $free = 0 } }
  if ($rt.ok -and $rt.out) { try { $total = [int](('' + ($rt.out | Select-Object -First 1)).Trim()) } catch { $total = 0 } }
  if ((Test-Path $EmbPortFile) -and ($total -gt 0)) { return $total }
  return $free
}

# Select-Tier -- walk the WINDOWS ladder top-down; the FIRST rung the host honestly clears
# wins. Sets script-scoped Tier/ModelId/Device/TierReason. Honors ACC_TIER override; the
# AWQ lanes are REFUSED on windows (no triton/AWQ wheels) and fall back to the probe.
$script:Tier = ''; $script:ModelId = ''; $script:Device = ''; $script:TierReason = ''
$script:ProbeGpu = 0; $script:ProbeVram = 0; $script:ProbeRam = 0
$script:TierForced = $false; $script:DiskFreeMb = -1; $script:HfCache = ''
function Select-Tier {
  $script:TierForced = $false
  $vram = Probe-VramFreeMb
  $ram  = Read-TotalRamMb
  $gpu  = 0; if ($vram -gt 0) { $gpu = 1 }
  $script:ProbeGpu = $gpu; $script:ProbeVram = $vram; $script:ProbeRam = $ram

  $forced = $env:ACC_TIER
  if ($forced) {
    switch ($forced) {
      '8b-full'   { $script:Tier = '8b-full'; $script:ModelId = 'TomoroAI/tomoro-colqwen3-embed-8b'; $script:Device = $(if ($gpu -eq 1) { 'cuda' } else { 'cpu' }) }
      '4b-full'   { $script:Tier = '4b-full'; $script:ModelId = 'TomoroAI/tomoro-colqwen3-embed-4b'; $script:Device = $(if ($gpu -eq 1) { 'cuda' } else { 'cpu' }) }
      'lateon'    { $script:Tier = 'lateon';  $script:ModelId = 'lightonai/LateOn'; $script:Device = 'cpu' }
      'container' { $script:Tier = 'container'; $script:ModelId = ''; $script:Device = '' }
      { $_ -in @('8b-awq', '4b-awq', '8b-cpu', '4b-cpu') } {
        Warn ("ACC_TIER=$forced is an AWQ/triton lane -- NO windows wheels exist (no triton on windows); ignoring, falling back to host probe")
        $forced = $null
      }
      default {
        Warn ("unknown ACC_TIER='$forced' -- ignoring, falling back to host probe")
        $forced = $null
      }
    }
    if ($forced) { $script:TierForced = $true; $script:TierReason = "forced via ACC_TIER=$forced"; return }
  }

  # 1-2: full bf16 on cuda -- NVIDIA present; torch-cuda resolves natively on windows.
  if (($gpu -eq 1) -and ($vram -ge $CUDA_8B_VRAM)) {
    $script:Tier = '8b-full'; $script:ModelId = 'TomoroAI/tomoro-colqwen3-embed-8b'; $script:Device = 'cuda'
    $script:TierReason = "GPU ${vram}MB free >= ${CUDA_8B_VRAM} -> ColQwen3-8B full bf16 on cuda (best multimodal; AWQ/triton has no windows wheels)"; return
  }
  if (($gpu -eq 1) -and ($vram -ge $CUDA_4B_VRAM)) {
    $script:Tier = '4b-full'; $script:ModelId = 'TomoroAI/tomoro-colqwen3-embed-4b'; $script:Device = 'cuda'
    $script:TierReason = "GPU ${vram}MB free >= ${CUDA_4B_VRAM} (< ${CUDA_8B_VRAM} for 8B) -> ColQwen3-4B full bf16 on cuda"; return
  }
  # 2.5: small-VRAM cuda -- a GPU is present but under the full-bf16 floors (e.g. a ~4GB laptop
  # GPU: the real 3938MiB install). Still run LateOn (dim-128, ~0.6GB) ON cuda rather than dropping
  # a present GPU to a 10-100x slower cpu encode. Mirrors src/selector.rs select_model_for_os.
  if (($gpu -eq 1) -and ($vram -ge $LATEON_VRAM)) {
    $script:Tier = 'lateon'; $script:ModelId = 'lightonai/LateOn'; $script:Device = 'cuda'
    $script:TierReason = "GPU ${vram}MB free >= ${LATEON_VRAM} (< ${CUDA_4B_VRAM} for 4B full) -> LateOn (text-only) on cuda -- small model fits the GPU"; return
  }
  # 3: LateOn -- the light text-only DEFAULT for any windows host with NO usable GPU. Windows has
  # no AWQ/triton lane AND no fresh cpu-ColQwen lane in the selector, so a no-GPU pick is LateOn
  # (matches src/selector.rs select_model_for_os windows branch + the cross-OS new-user default:
  # a fast ~0.6GB first run, not a multi-GB ColQwen-on-cpu grind). Multimodal needs a cuda GPU,
  # or ACC_TIER=8b-full/4b-full to force ColQwen on cpu; a pinned cuda model still degrades to cpu
  # (recoverable) at runtime via the daemon-start device re-validation.
  if ($ram -ge $LATEON_RAM) {
    $script:Tier = 'lateon'; $script:ModelId = 'lightonai/LateOn'; $script:Device = 'cpu'
    $script:TierReason = "no usable GPU (free VRAM ${vram}MB) -> LateOn (light text-only default; multimodal needs a cuda GPU or ACC_TIER) on cpu"; return
  }
  # 6: nothing viable natively -> the container tier path.
  $script:Tier = 'container'; $script:ModelId = ''; $script:Device = ''
  $script:TierReason = "no native tier viable (RAM ${ram}MB) -> use the CONTAINER tier (docs/INSTALL_CONTAINER.md)"
}

# Apply-DiskFloor -- the tier ladder's DISK leg (mirror of install.sh apply_disk_floor):
# the pick's expected download + 2048MB headroom must fit the free disk at the HF cache,
# else degrade ONE RUNG AT A TIME (8b-full -> 4b-full -> lateon), noting
# 'disk floor: need ~XGB, have ~YGB' in TierReason. A forced ACC_TIER is the owner's
# pick -- never degraded, but an unfittable pick is warned honestly. Unknown free disk
# (PSDrive probe failed) skips the floor with an explicit note.
function Apply-DiskFloor {
  if (-not $script:ModelId) { return }   # container tier: nothing to download
  $need = (Get-ExpectedModelMb $script:Tier) + $DISK_HEADROOM_MB
  if ($script:DiskFreeMb -le 0) {
    $script:TierReason += " - disk floor not applied (free disk unknown at $($script:HfCache))"
    return
  }
  if ($script:TierForced) {
    if ($need -gt $script:DiskFreeMb) {
      Warn ("forced tier $($script:Tier) needs ~$(MbToGb $need)GB free disk (model + 2GB headroom) but only ~$(MbToGb $script:DiskFreeMb)GB is free at $($script:HfCache) -- the download may fail")
    }
    return
  }
  while ($need -gt $script:DiskFreeMb) {
    $needG = MbToGb $need; $haveG = MbToGb $script:DiskFreeMb
    if ($script:Tier -eq 'lateon') {
      $script:TierReason += " - disk floor UNMET even for LateOn: need ~${needG}GB, have ~${haveG}GB -- the download may fail"
      break
    }
    if ($script:Tier -eq '8b-full') {
      $script:Tier = '4b-full'; $script:ModelId = 'TomoroAI/tomoro-colqwen3-embed-4b'   # device unchanged
    } else {
      $script:Tier = 'lateon'; $script:ModelId = 'lightonai/LateOn'; $script:Device = 'cpu'
    }
    $script:TierReason += " - disk floor: need ~${needG}GB, have ~${haveG}GB -> degraded to $($script:Tier)"
    $need = (Get-ExpectedModelMb $script:Tier) + $DISK_HEADROOM_MB
  }
}

# -- phase 0 banner + selection -----------------------------------------------------------
Step 'phase 0 -- probe host + select embedder tier'
if ($DryRun) { Say '(dry-run: walking every phase, mutating NOTHING)' }
Say 'acc is a Work Model + tool loop for Claude Code: retrieve from your scored Work Model, run sandboxed actions, learn from real outcomes.'
$OsBuild = Get-OsBuild
$Arch = Get-Arch
Say ("host: $OsBuild / $Arch - substrate: $DbPath")
if (-not $script:OnWindows) { Warn 'non-windows host -- install.ps1 is the native WINDOWS lane; this run is a cross-platform dry-run self-test only (POSIX hosts: ./install.sh)' }
Select-Tier
$script:HfCache = Get-HfCacheDir
$script:DiskFreeMb = Probe-FreeDiskMb
Apply-DiskFloor
Say ("probe: gpu=$script:ProbeGpu vram_free=$($script:ProbeVram)MB ram=$($script:ProbeRam)MB arch=$Arch disk_free=$($script:DiskFreeMb)MB (hf cache: $($script:HfCache)) (windows ladder: full bf16 only, never AWQ/triton)")
if ($script:Tier -eq 'container') {
  # Container is a TERMINAL verdict -- no native lane fits, the native phases don't apply.
  Emit-Phase 'probe_tier' 'ok' ("$script:TierReason -> tier=container") 'no native lane fits -- follow docs/INSTALL_CONTAINER.md (Docker image carries deps + CPU floor)'
  Warn 'No native embedder tier fits this host. The container tier is the portability floor.'
  Warn '-> docs/INSTALL_CONTAINER.md  (scripts/acc-docker.sh)'
  if ($Json) { Emit-Phase 'verdict' 'skipped' ("native install not viable; container tier required ($script:TierReason)") 'docs/INSTALL_CONTAINER.md - scripts/acc-docker.sh' }
  exit 0
}
Emit-Phase 'probe_tier' 'ok' ("tier=$script:Tier model=$script:ModelId device=$script:Device - $script:TierReason") 'phase 1: prereqs (rust/uv/git)'

# Real installs only mutate WINDOWS hosts; everything below stays a dry walk elsewhere.
if ((-not $DryRun) -and (-not $script:OnWindows)) {
  Emit-Phase 'verdict' 'failed' 'install.ps1 is the native Windows installer -- a real run on a POSIX host is refused' 'run ./install.sh on linux/macOS (or .\install.ps1 -DryRun here for the self-test)'
  exit 1
}

# =========================================================================================
# PHASE 1 -- prereqs: rust (rustup-init.exe), uv (official installer), python (uv-managed),
# git. Idempotent: present -> skip. Mirrors install.sh phase 1, transposed to windows.
# =========================================================================================
Step 'phase 1 -- prereqs (rust - uv - python - git)'
# rust
if (Have 'cargo') {
  $cv = ''; $r = Invoke-Native 'cargo' @('--version'); if ($r.ok -and $r.out) { $cv = (('' + ($r.out | Select-Object -First 1)) -split '\s+')[1] }
  Emit-Phase 'prereq_rust' 'ok' ("cargo present ($cv)")
} else {
  $rustupOk = Act 'install rustup (rustup-init.exe, non-interactive: -y --no-modify-path)' {
    $rustupUrl = 'https://win.rustup.rs/x86_64'
    if ((Get-Arch) -match 'ARM64|Aarch64') { $rustupUrl = 'https://win.rustup.rs/aarch64' }
    $exe = Join-Path ([IO.Path]::GetTempPath()) 'rustup-init.exe'
    Invoke-WebRequest -Uri $rustupUrl -OutFile $exe -UseBasicParsing
    $p = Start-Process -FilePath $exe -ArgumentList '-y', '--no-modify-path' -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) { throw "rustup-init.exe exit $($p.ExitCode)" }
  }
  if ($rustupOk) {
    $cargoBin = Join-Path (Join-Path $HOME '.cargo') 'bin'
    if (Test-Path $cargoBin) { $env:Path = $cargoBin + [IO.Path]::PathSeparator + $env:Path }
    $st = 'ok'; if ($DryRun) { $st = 'would' }
    Emit-Phase 'prereq_rust' $st 'rust toolchain installed (MSVC host triple)' 'phase 1: uv'
  } else {
    Emit-Phase 'prereq_rust' 'failed' 'rustup install failed' 'install rust manually: https://rustup.rs (rustup-init.exe)'
    exit 1
  }
}
# uv
if (Have 'uv') {
  $uvv = ''; $r = Invoke-Native 'uv' @('--version'); if ($r.ok -and $r.out) { $uvv = (('' + ($r.out | Select-Object -First 1)) -split '\s+')[1] }
  Emit-Phase 'prereq_uv' 'ok' ("uv present ($uvv)")
} else {
  $uvOk = Act 'install uv (official installer: irm https://astral.sh/uv/install.ps1 | iex)' {
    $uvInstaller = Invoke-RestMethod -Uri 'https://astral.sh/uv/install.ps1' -UseBasicParsing
    Invoke-Expression $uvInstaller
  }
  if ($uvOk) {
    foreach ($d in @((Join-Path (Join-Path $HOME '.local') 'bin'), (Join-Path (Get-WinLocalAppData) 'uv\bin'))) {
      if (Test-Path $d) { $env:Path = $d + [IO.Path]::PathSeparator + $env:Path }
    }
    $st = 'ok'; if ($DryRun) { $st = 'would' }
    Emit-Phase 'prereq_uv' $st 'uv installed' 'phase 1: python'
  } else {
    Emit-Phase 'prereq_uv' 'failed' 'uv install failed' 'install uv manually: https://astral.sh/uv'
    exit 1
  }
}
# python -- uv provisions the encoder env's interpreter (PEP-723 script deps), so a system
# python is NOT a hard requirement on windows (install.ps1 needs no python helpers: JSON
# emission is native PowerShell, unlike install.sh's python3 lane).
if (Have 'python') {
  $pyv = ''; $r = Invoke-Native 'python' @('--version'); if ($r.ok -and $r.out) { $pyv = (('' + ($r.out | Select-Object -First 1)) -split '\s+')[-1] }
  Emit-Phase 'prereq_python' 'ok' ("python present ($pyv)")
} else {
  Emit-Phase 'prereq_python' 'ok' 'no system python -- fine on windows: uv provisions the encoder env interpreter (phase 4); installer JSON is native PowerShell'
}
# git -- needed for clone/update flows, source fallback, and POSIX hook-script shells.
if (Have 'git') {
  $gv = ''; $r = Invoke-Native 'git' @('--version'); if ($r.ok -and $r.out) { $gv = (('' + ($r.out | Select-Object -First 1)) -split '\s+')[-1] }
  Emit-Phase 'prereq_git' 'ok' ("git present ($gv)")
} else {
  $gitOk = $false
  if ($script:OnWindows) {
    $gitOk = Install-WingetPackage 'Git.Git' 'Git for Windows'
    foreach ($d in @((Join-Path $env:ProgramFiles 'Git\cmd'), (Join-Path $env:ProgramFiles 'Git\bin'), (Join-Path ${env:ProgramFiles(x86)} 'Git\cmd'))) {
      if ($d -and (Test-Path $d)) { $env:Path = $d + [IO.Path]::PathSeparator + $env:Path }
    }
  }
  if ($gitOk) {
    $st = 'ok'; if ($DryRun) { $st = 'would' }
    Emit-Phase 'prereq_git' $st 'Git for Windows installed via winget (clone/update/source fallback available)' 'phase 2: system deps'
  } else {
    Emit-Phase 'prereq_git' 'skipped' 'git not found and winget is unavailable or failed -- repo updates/source fallback may be limited' 'install Git for Windows: winget install Git.Git (https://git-scm.com/download/win)'
  }
}

# =========================================================================================
# PHASE 2 -- system deps: MSVC linker (VS Build Tools) + sandbox note. Mirrors install.sh
# phase 2; on windows there is no bwrap and no system-sqlite step (rusqlite is bundled
# on windows via Cargo.toml's [target.'cfg(windows)'.dependencies] block).
# =========================================================================================
Step 'phase 2 -- system deps (MSVC linker + sandbox)'
# VS Build Tools / link.exe -- cargo's MSVC target needs it for source fallback.
function Test-MsvcLinker {
  if (Have 'link.exe') { return $true }
  $pf86 = ${env:ProgramFiles(x86)}
  if ($pf86) {
    $vswhere = Join-Path $pf86 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
      $r = Invoke-Native $vswhere @('-latest', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath')
      if ($r.ok -and $r.out) { return $true }
    }
  }
  return $false
}
$HasMsvc = $false
if ($script:OnWindows) { $HasMsvc = Test-MsvcLinker }
if ($HasMsvc) {
  Emit-Phase 'sysdeps_msvc' 'ok' 'MSVC linker present (link.exe / VC.Tools via vswhere) -- cargo can link'
} elseif (-not $script:OnWindows) {
  Emit-Phase 'sysdeps_msvc' 'skipped' 'non-windows dry-run host -- MSVC probe not applicable here'
} else {
  $msvcOk = Install-WingetPackage 'Microsoft.VisualStudio.2022.BuildTools' 'VS Build Tools (VC toolchain)' @(
    '--override',
    '--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --quiet --wait --norestart'
  )
  if ($msvcOk) {
    $st = 'ok'; if ($DryRun) { $st = 'would' }
    Emit-Phase 'sysdeps_msvc' $st 'VS Build Tools installed via winget (VC toolchain for cargo source fallback)' 'phase 3: binary'
  } else {
    Emit-Phase 'sysdeps_msvc' 'skipped' 'link.exe NOT found and winget is unavailable or failed -- prebuilt install can still work, source fallback needs VS Build Tools' 'winget install Microsoft.VisualStudio.2022.BuildTools --override "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --quiet --wait --norestart" (or https://visualstudio.microsoft.com/visual-cpp-build-tools/), then re-run .\install.ps1'
  }
}
# sandbox -- no bwrap on windows; mirror of install.sh's macOS branch, stated honestly.
Emit-Phase 'sysdeps_sandbox' 'skipped' "windows: no bwrap -- exec runtimes run under acc's built-in deadline only (sandbox windows lane pending). sqlite: bundled in the windows build, no system package needed"

# =========================================================================================
# PHASE 3 -- binary: PREBUILT FETCH -> SOURCE BUILD. Idempotent postcondition = `acc`
# resolves AND its identity (token 2 of `acc --version`: `<ver>+<sha>`) matches the
# checkout's crate version + git short HEAD (no .git -> version-only compare, noted).
# Branch order mirrors install.sh phase 3: (a) postcondition match -> keep installed;
# (b) prebuilt fetch (unless ACC_INSTALL=source) -- download the release artifact +
# sha256sums.txt, VERIFY the sha256 with Get-FileHash (an unverified binary is NEVER
# installed), unpack acc.exe to the user bin dir -- no VS Build Tools needed; (c) source
# build fallback -- the previous behavior verbatim -- when the fetch fails for ANY reason
# (a fetch failure never fails the install while this fallback exists). --locked: a fresh
# resolve can pick a newer patch that breaks the build. ENGINE HONESTY: the windows engine
# port is in flight -- a build failure here is reported honestly (failed + pending note)
# and the walk CONTINUES so config + wiring still land (the one deviation from
# install.sh's exit-1; see header).
# =========================================================================================
Step 'phase 3 -- install acc (prebuilt fetch -> source build)'
# Latest-release-tag version resolver (mirrors src/update.rs release_url/tag_name, ~lines
# 312/501): GET the releases/latest API, read .tag_name (e.g. "v0.1.0"), strip leading "v"
# -> the version. This is the ONLY version source on the public binary-only path (no
# Cargo.toml). Source-clone path: Cargo.toml wins and this is never called. Fail-soft: any
# failure (offline / rate-limit / non-2xx / no published release yet -- the v0.1.0 release
# may still be a DRAFT, so /latest can 404) returns '' and the prebuilt lane refuses honestly.
$ReleaseApi = 'https://api.github.com/repos/maxbaluev/accreted-intelligence/releases/latest'
function Resolve-LatestVersion {
  try {
    $resp = Invoke-RestMethod -Uri $ReleaseApi -Headers @{ 'Accept' = 'application/vnd.github+json'; 'User-Agent' = 'acc-install' } -TimeoutSec 30 -UseBasicParsing
    $tag = ('' + $resp.tag_name).Trim()
    if ($tag -match '^v(.+)$') { return $Matches[1] }
    return $tag
  } catch { return '' }
}

$SrcVer = ''
$CargoToml = Join-Path $Repo 'Cargo.toml'
if (Test-Path $CargoToml) {
  $vm = Select-String -Path $CargoToml -Pattern '^version\s*=\s*"([^"]+)"' | Select-Object -First 1
  if ($vm) { $SrcVer = $vm.Matches[0].Groups[1].Value }
} else {
  # Public binary-only path: no Cargo.toml (no engine source). Resolve the version from the
  # latest published release tag so the artifact name (acc-v<ver>-<target>) is correct; the
  # fetch+verify+source-fallback walk below is unchanged. Do NOT abort -- a prebuilt may exist.
  $SrcVer = Resolve-LatestVersion
  if ($SrcVer) { Say ("resolved acc v$SrcVer from the latest published release tag (no Cargo.toml -- binary-only install)") }
}
$HeadSha = ''
if (Have 'git') {
  $r = Invoke-Native 'git' @('-C', $Repo, 'rev-parse', '--short', 'HEAD')
  if ($r.ok -and $r.out) { $HeadSha = ('' + ($r.out | Select-Object -First 1)).Trim() }
}

# Version probe -- token 2 of the identity line `acc <ver>+<sha> (<target>)`. (The old
# last-word parse yielded `(<target>)` and could never match -- tests/build_identity.rs (c).)
$InstalledId = ''
if (Have 'acc') {
  $r = Invoke-Native 'acc' @('--version')
  if ($r.ok -and $r.out) {
    $words = @((('' + ($r.out | Select-Object -First 1)).Trim() -split '\s+'))
    if ($words.Count -ge 2) { $InstalledId = $words[1] }
  }
}
$InstalledVer = $InstalledId; $InstalledSha = ''
if ($InstalledId -match '\+') {
  $idParts = $InstalledId -split '\+', 2
  $InstalledVer = $idParts[0]; $InstalledSha = $idParts[1]
}
$IdMatch = $false; $IdNote = ''
if ($SrcVer -and ($InstalledVer -eq $SrcVer)) {
  if ($HeadSha) {
    if ($InstalledSha -eq $HeadSha) { $IdMatch = $true }
  } else {
    $IdMatch = $true; $IdNote = ' -- no .git: sha not compared, crate version only'
  }
}

# Prebuilt lane facts -- release.yml naming contract: acc-<version>-<target>.zip +
# sha256sums.txt, where <version> = the pushed tag (vX.Y.Z) on tag-push releases.
$PrebuiltTarget = 'x86_64-pc-windows-msvc'
$ReleaseBase = 'https://github.com/maxbaluev/accreted-intelligence/releases'
$Artifact = "acc-v$SrcVer-$PrebuiltTarget.zip"
$UserBinDir = Join-Path (Join-Path $HOME '.local') 'bin'
$InstallSource = ($env:ACC_INSTALL -eq 'source')
$script:PrebuiltId = ''; $script:PrebuiltSrc = ''

# Invoke-PrebuiltFetch -- $true = a sha256-VERIFIED release acc.exe now lives in
# $UserBinDir (script:PrebuiltId/PrebuiltSrc set); $false on ANY failure -> caller falls
# back to the source build. Tries the version-tagged URL (v$SrcVer) first, then /latest/.
# Refusal rules: missing manifest entry or a hash MISMATCH REFUSE the binary -- it is
# deleted with the tmp dir and never reaches the bin dir.
function Invoke-PrebuiltFetch {
  if (-not $SrcVer) { Say 'acc version unresolved (no Cargo.toml and no published release tag) -- building from source'; return $false }
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ('acc-prebuilt-' + [IO.Path]::GetRandomFileName())
  try {
    $null = New-Item -ItemType Directory -Path $tmp -Force
    $fetched = $false; $src = ''
    foreach ($base in @("$ReleaseBase/download/v$SrcVer", "$ReleaseBase/latest/download")) {
      Say ("trying prebuilt: $base/$Artifact")
      try {
        Invoke-WebRequest -Uri "$base/$Artifact" -OutFile (Join-Path $tmp $Artifact) -UseBasicParsing
        Invoke-WebRequest -Uri "$base/sha256sums.txt" -OutFile (Join-Path $tmp 'sha256sums.txt') -UseBasicParsing
        $fetched = $true; $src = $base; break
      } catch { continue }
    }
    if (-not $fetched) { Say 'no prebuilt release reachable -- building from source'; return $false }
    # VERIFY -- sha256sum -c semantics: the manifest line for THIS artifact must match.
    $want = ''
    foreach ($line in @(Get-Content (Join-Path $tmp 'sha256sums.txt'))) {
      $p = @(('' + $line).Trim() -split '\s+', 2)
      if (($p.Count -eq 2) -and ($p[1].TrimStart('*') -eq $Artifact)) { $want = $p[0].ToLowerInvariant(); break }
    }
    if (-not $want) {
      Warn ("sha256sums.txt has no entry for $Artifact -- REFUSING the unverified binary; building from source")
      return $false
    }
    $got = (Get-FileHash -Algorithm SHA256 -Path (Join-Path $tmp $Artifact)).Hash.ToLowerInvariant()
    if ($got -ne $want) {
      Warn ("sha256 MISMATCH for $Artifact (expected $want, got $got) -- REFUSING the unverified binary; building from source")
      return $false
    }
    Ok ("sha256 verified: $Artifact matches sha256sums.txt")
    # Unpack + re-probe in tmp BEFORE installing -- a wrong-version binary never lands.
    Expand-Archive -Path (Join-Path $tmp $Artifact) -DestinationPath $tmp -Force
    $exe = Join-Path $tmp 'acc.exe'
    if (-not (Test-Path $exe)) { Warn ("$Artifact did not contain acc.exe -- building from source"); return $false }
    $newId = ''
    $r = Invoke-Native $exe @('--version')
    if ($r.ok -and $r.out) {
      $w = @((('' + ($r.out | Select-Object -First 1)).Trim() -split '\s+'))
      if ($w.Count -ge 2) { $newId = $w[1] }
    }
    if (-not ($newId -like ($SrcVer + '+*'))) {
      Warn ("prebuilt binary reports '$newId' (wanted $SrcVer+<sha>) -- building from source")
      return $false
    }
    $null = New-Item -ItemType Directory -Path $UserBinDir -Force
    $accExe = Join-Path $UserBinDir 'acc.exe'
    Move-Item -Path $exe -Destination $accExe -Force
    # FREE Windows trust (no paid code-signing cert): Invoke-WebRequest stamps the Mark-of-the-Web
    # (Zone.Identifier ADS) on downloads, which makes Defender/SmartScreen scan-gate the file.
    # Unblock-File strips it so the CLI runs without a SmartScreen prompt. Integrity is already
    # covered by the sha256 verify above (a tampered acc.exe is REFUSED). Proper code-signing
    # (Azure Trusted Signing ~$10/mo, or an EV cert) is only needed for direct .exe / GUI launches.
    Unblock-File -Path $accExe -ErrorAction SilentlyContinue
    # hash -r equivalent: re-prepend the bin dir on this session's PATH so Get-Command
    # re-resolves acc fresh (PowerShell has no command hash table to flush).
    $env:Path = $UserBinDir + [IO.Path]::PathSeparator + $env:Path
    $script:PrebuiltId = $newId; $script:PrebuiltSrc = $src
    return $true
  } catch {
    Warn ('prebuilt fetch failed: ' + $_.Exception.Message + ' -- building from source')
    return $false
  } finally {
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
  }
}

$Acc = Join-Path (Join-Path (Join-Path $Repo 'target') 'release') 'acc.exe'
$BinaryAvailable = $false
if ($IdMatch) {
  $Acc = (Get-Command 'acc').Source
  $BinaryAvailable = $true
  Emit-Phase 'binary' 'ok' ("acc $InstalledId already installed at $Acc (matches checkout$IdNote)")
} elseif ($DryRun) {
  # Dry-run honesty: report the would-fetch artifact + would-verify line, NO network.
  if ($InstallSource) {
    Say 'ACC_INSTALL=source -- prebuilt lane skipped, would build from source'
    Say 'WOULD: cargo build --release --locked'
    Say 'WOULD: cargo install --path . --locked --force'
    Emit-Phase 'binary' 'would' ("acc built + installed from source (ACC_INSTALL=source; engine windows port in flight -- the build is the honest gate)") 'phase 4: encoder env'
  } else {
    Say ("WOULD: fetch $Artifact (try $ReleaseBase/download/v$SrcVer first, then $ReleaseBase/latest/download)")
    Say ("WOULD: verify sha256 of $Artifact against sha256sums.txt (Get-FileHash) -- refuse on mismatch, an unverified binary is never installed")
    Say ("WOULD: unpack acc.exe to $UserBinDir, refresh PATH, re-probe acc --version (token 2: <ver>+<sha>)")
    Say 'WOULD: fall back to the source build (cargo build --release --locked) if no release is reachable'
    Emit-Phase 'binary' 'would' ("prebuilt $Artifact fetched + sha256-verified into $UserBinDir (source build is the fallback)") 'phase 4: encoder env'
  }
} elseif ((-not $InstallSource) -and (Invoke-PrebuiltFetch)) {
  $Acc = Join-Path $UserBinDir 'acc.exe'
  $BinaryAvailable = $true
  # PERSIST PATH (mirror of how rustup persists ~/.cargo/bin): the session-only PATH edit in
  # Invoke-PrebuiltFetch dies with this process -- a NEW terminal would get "acc: command not
  # found". Add $UserBinDir to the User-scoped PATH (User registry env), idempotent: a
  # contains-check (case-insensitive, ;-split) skips the rewrite if it is already present.
  if ($script:OnWindows -and (-not $DryRun)) {
    try {
      $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
      $segments = @()
      if ($userPath) { $segments = @($userPath -split ';' | Where-Object { $_ -ne '' }) }
      $already = $false
      foreach ($seg in $segments) { if ($seg.TrimEnd('\') -ieq $UserBinDir.TrimEnd('\')) { $already = $true; break } }
      if (-not $already) {
        $newUserPath = if ($userPath) { $userPath.TrimEnd(';') + ';' + $UserBinDir } else { $UserBinDir }
        [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
        Say ("persisted $UserBinDir to your User PATH (new terminals will resolve acc; this session already has it)")
      } else {
        Say ("$UserBinDir already on your User PATH -- no change")
      }
    } catch { Warn ('could not persist User PATH: ' + $_.Exception.Message + ' -- add ' + $UserBinDir + ' to PATH manually so new terminals resolve acc') }
  }
  $skew = ''
  if ($HeadSha -and ($script:PrebuiltId -ne ($SrcVer + '+' + $HeadSha))) { $skew = " (binary sha differs from checkout HEAD $HeadSha -- built from the release tag)" }
  Emit-Phase 'binary' 'ok' ("prebuilt acc $($script:PrebuiltId) installed at $Acc -- sha256-verified from $($script:PrebuiltSrc), no VS Build Tools needed$skew") 'phase 4: encoder env'
} else {
  if ($InstallSource) { Say 'ACC_INSTALL=source -- prebuilt lane skipped, building from source' }
  Say 'cargo build --release --locked (this is the honest gate for the in-flight windows engine port)'
  $built = Invoke-NativeChatter 'cargo' @('build', '--release', '--locked')
  if ($built) {
    $installed = Invoke-NativeChatter 'cargo' @('install', '--path', $Repo, '--locked', '--force')
    if ($installed -and (Have 'acc')) { $Acc = (Get-Command 'acc').Source }
    if (Test-Path $Acc) {
      $BinaryAvailable = $true
      Emit-Phase 'binary' 'ok' ("acc built + installed at $Acc") 'phase 4: encoder env'
    } else {
      Emit-Phase 'binary' 'failed' 'cargo build succeeded but no acc binary resolved' 'check cargo install output, then re-run .\install.ps1'
    }
  } else {
    Emit-Phase 'binary' 'failed' ("cargo build failed -- $EnginePendingNote") 'watch the acc repo for the windows engine port; re-run .\install.ps1 once it lands (config + Claude Code wiring below still install now)'
  }
}

# =========================================================================================
# PHASE 3b -- plugins on disk (mirrors install.sh phase 3b; solved:a78f0ba601287cad). A
# binary-only release ships ONLY the `acc` binary -- no plugins/ tree. Without this,
# detect_repo_root falls back to the build-host path and the OpenCode/Codex convergers write
# a DEAD plugin/notify path into the user's configs (silently breaking OpenCode plugin-load +
# Codex notify). Fix: provision plugins/ into the per-user data dir (%APPDATA%\acc -- the same
# dir platform::data_dir() resolves to on Windows and detect_repo_root probes), then export
# ACC_REPO_ROOT to it so the hosts-sync phase wires the REAL on-disk path. Source: copy the
# local plugins/ when present (install-from-clone); else FETCH from the public raw URLs
# (mirrors the prebuilt fetch). Idempotent; fail-soft (hosts-sync skips the field rather than
# writing a dead path).
# =========================================================================================
Step 'phase 3b -- provision plugins/ to the per-user data dir (%APPDATA%\acc)'
$PluginsDest    = Join-Path $ConfigHome 'plugins'
$PluginsMarkerA = Join-Path $PluginsDest 'opencode\acc.ts'
$PluginsMarkerB = Join-Path $PluginsDest 'codex\notify-acc.sh'
$PluginsFiles   = @(
  'opencode/acc.ts', 'opencode/opencode.json.snippet', 'opencode/README.md',
  'codex/notify-acc.sh', 'codex/hooks.json', 'codex/config.toml.snippet', 'codex/README.md',
  'cursor/rules-acc.mdc', 'cursor/hooks.json', 'cursor/mcp.json', 'cursor/README.md', 'README.md'
)
$PluginsRawBase = 'https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/plugins'
$LocalPlugins   = Join-Path $Repo 'plugins'
$LocalMarker    = Join-Path $LocalPlugins 'opencode\acc.ts'
if ($DryRun) {
  if (Test-Path $LocalMarker) {
    Say "WOULD: copy $LocalPlugins -> $PluginsDest (local tree present)"
  } else {
    Say "WOULD: fetch plugins/ from $PluginsRawBase -> $PluginsDest (no local tree -- bare-binary path)"
  }
  Emit-Phase 'plugins' 'would' "provision plugins/ into $PluginsDest (probed by detect_repo_root; convergers wire the REAL path)" 'phase 4: encoder env'
} else {
  $PluginsOk = $false
  if ((Test-Path $PluginsMarkerA) -and (Test-Path $PluginsMarkerB)) {
    Say "plugins already provisioned at $PluginsDest"
    $PluginsOk = $true
  } elseif (Test-Path $LocalMarker) {
    # (a) install-from-clone: copy the local plugins/ tree verbatim.
    try {
      New-Item -ItemType Directory -Force -Path $PluginsDest | Out-Null
      Copy-Item -Path (Join-Path $LocalPlugins '*') -Destination $PluginsDest -Recurse -Force
      Ok "plugins copied from $LocalPlugins -> $PluginsDest"
      $PluginsOk = $true
    } catch { Warn "copy from $LocalPlugins failed: $_" }
  } else {
    # (b) bare-binary path: FETCH the tree from the public raw URLs (Invoke-WebRequest is
    # built in -- no curl dependency). Fail-soft: a partial fetch leaves the markers absent
    # and hosts-sync then skips the plugin/notify field (never a dead path).
    $got = 0
    foreach ($f in $PluginsFiles) {
      $dest = Join-Path $PluginsDest ($f -replace '/', '\')
      New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
      try {
        Invoke-WebRequest -UseBasicParsing -Uri "$PluginsRawBase/$f" -OutFile $dest -TimeoutSec 60
        $got++
      } catch { }
    }
    if ((Test-Path $PluginsMarkerA) -and (Test-Path $PluginsMarkerB)) {
      Ok "plugins fetched ($got files) from $PluginsRawBase -> $PluginsDest"
      $PluginsOk = $true
    } else {
      Warn "plugins fetch incomplete (markers missing) -- hosts-sync will skip plugin/notify wiring (no dead path)"
    }
  }
  if ($PluginsOk) {
    $env:ACC_REPO_ROOT = $ConfigHome
    Emit-Phase 'plugins' 'ok' "plugins at $PluginsDest; ACC_REPO_ROOT -> $ConfigHome (convergers wire the real path)" 'phase 4: encoder env'
  } else {
    Emit-Phase 'plugins' 'skipped' 'no local plugins/ and fetch failed -- hosts-sync skips plugin/notify wiring (no dead path written)' 'phase 4: encoder env'
  }
}

# =========================================================================================
# PHASE 4 -- encoder env: materialize the tier's Python deps with `uv sync --script`
# (PEP-723 inline deps; PEP508 markers resolve torch/torch-cuda natively per platform --
# the SAME encoders/li_encode.py lane install.sh uses for full/LateOn tiers). Pays the
# resolve/download cost ONCE, before the daemon's first encode. Idempotent (uv caches).
# =========================================================================================
Step 'phase 4 -- encoder env (uv sync of the tier script deps)'
# Resolve the encoder-env-warm path. A DEV checkout ships encoders\li_encode.py on disk ->
# `uv sync --script <file>`. A binary-only RELEASE install ships no encoders\ dir -> the encoder
# scripts are embedded in the binary and reachable as `acc warm-encoder <model>` (probe with
# --help), which materializes the tier's encoder and `uv sync --script`s it with VISIBLE uv
# progress and WITHOUT loading the model. Either path resolves+caches the (multi-GB)
# torch/transformers/awq/flash-attn env once, before the daemon's first encode. Mirrors install.sh
# phase 4 and the phase-6 prefetch binary fallback.
if (Test-Path $EncoderScript) {
  $synced = Act ("uv sync --script li_encode.py (resolve+cache the $script:Tier encoder deps; PEP508 markers pick the windows torch lane)") {
    $r = Invoke-Native 'uv' @('sync', '--script', $EncoderScript)
    if (-not $r.ok) { throw 'uv sync --script reported an issue' }
  }
  if ($synced) {
    $st = 'ok'; if ($DryRun) { $st = 'would' }
    Emit-Phase 'encoder_env' $st ("encoder env ready for $script:Tier (li_encode.py deps resolved/cached)") 'phase 5: model pin'
  } else {
    Emit-Phase 'encoder_env' 'skipped' 'uv sync --script reported an issue (deps resolve lazily on first encode)' ("re-run; or check: uv sync --script $EncoderScript")
  }
} else {
  $accHasWarm = $false
  if ($script:ModelId) { try { & $Acc warm-encoder --help *> $null; $accHasWarm = ($LASTEXITCODE -eq 0) } catch { $accHasWarm = $false } }
  if ($accHasWarm) {
    # Binary-only release install: on-disk encoders\ absent but the binary carries the embedded
    # encoder scripts. Warm the env via the binary so the wheel download is VISIBLE here instead
    # of hidden inside the first embedder start.
    if ($DryRun) {
      Say ("WOULD: acc warm-encoder $script:ModelId (uv sync --script the tier's embedded encoder env, live progress, no model load)")
      Emit-Phase 'encoder_env' 'would' ("warm the encoder env for $script:Tier via acc warm-encoder $script:ModelId (torch/transformers/... -- several GB, one time)") 'phase 5: model pin'
    } else {
      Say ("resolving the encoder env (torch/transformers/... -- several GB, one time)...")
      $warmOk = $false
      $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
      try { & $Acc warm-encoder $script:ModelId; $warmOk = ($LASTEXITCODE -eq 0) } catch { $warmOk = $false }
      finally { $ErrorActionPreference = $prev }
      if ($warmOk) {
        Emit-Phase 'encoder_env' 'ok' ("encoder env ready for $script:Tier (acc warm-encoder $script:ModelId -- torch/transformers/... resolved/cached)") 'phase 5: model pin'
      } else {
        Emit-Phase 'encoder_env' 'skipped' 'acc warm-encoder reported an issue (deps resolve lazily on first encode)' 're-run; or let the daemon resolve the env lazily on first start'
      }
    }
  } else {
    Emit-Phase 'encoder_env' 'skipped' ("no encoder env to warm for tier=$script:Tier (on-disk $EncoderScript absent and the binary has no warm-encoder subcommand, or no model pinned)") 'tier mis-selected -- check phase 0'
  }
}

# =========================================================================================
# PHASE 5 -- model pin: record the install-time (model, device) BEFORE VRAM is taken.
# Windows config-home contract: %APPDATA%\acc\model.json (the same home as the auth store,
# src/brain.rs default_auth_path). `acc pin` re-runs the selector ladder host-side.
# ENGINE HONESTY: needs the built binary -- degrades with the pending note until then.
# =========================================================================================
Step 'phase 5 -- pin the embedder model (install-time, before VRAM is taken)'
$PinPath = Join-Path $ConfigHome 'model.json'
if ($DryRun) {
  Emit-Phase 'model_pin' 'would' ("pin $script:ModelId on $script:Device -> $PinPath") 'phase 6: model prefetch'
} elseif (-not $BinaryAvailable) {
  Emit-Phase 'model_pin' 'skipped' ("pin requires the acc binary -- $EnginePendingNote") 're-run .\install.ps1 after the engine port lands; or: acc pin'
} else {
  $r = Invoke-Native $Acc @('pin')
  if ($r.ok) {
    $pinned = "$script:ModelId on $script:Device"
    if (Test-Path $PinPath) {
      try { $pj = Get-Content $PinPath -Raw | ConvertFrom-Json; $pinned = ('' + $pj.model_id + ' on ' + $pj.device) } catch { }
    }
    Emit-Phase 'model_pin' 'ok' ("pinned $pinned -> $PinPath") 'phase 6: model prefetch'
  } else {
    Emit-Phase 'model_pin' 'skipped' 'pin failed -- clients fall back to a live probe' 're-run, or: acc pin'
  }
}

# =========================================================================================
# PHASE 6 -- model prefetch: pull the pinned model into the HF cache NOW, with VISIBLE
# progress (uv run encoders\prefetch.py -- snapshot_download's native resume + cache
# reuse), instead of hiding an up-to-8.3GB download inside the daemon-warm phase.
# Idempotent: a cache hit returns instantly. Prefetch is UX, not a dependency -- a
# network failure is 'skipped' and the daemon still downloads lazily on first start.
# Mirrors install.sh phase 6 (model_prefetch).
# =========================================================================================
Step 'phase 6 -- model prefetch (weights into the HF cache, visible progress)'
$PrefetchScript = Join-Path (Join-Path $Repo 'encoders') 'prefetch.py'
$ExpMb = Get-ExpectedModelMb $script:Tier
$NeedMb = $ExpMb + $DISK_HEADROOM_MB
# Resolve the prefetch command. Dev checkouts ship encoders\prefetch.py -> run it via uv.
# A binary-only RELEASE install ships no encoders\ dir -> the script is embedded in the binary
# and reachable as `acc prefetch` (probe with --help). Either way the weights download with
# huggingface_hub's live progress. No command -> the prefetch is skipped (daemon downloads lazily).
$PrefetchExe = $null; $PrefetchLead = @(); $PrefetchDisplay = $null
if (Test-Path $PrefetchScript) {
  $PrefetchExe = 'uv'; $PrefetchLead = @('run', $PrefetchScript); $PrefetchDisplay = 'uv run encoders\prefetch.py'
} else {
  $accHasPrefetch = $false
  try { & $Acc prefetch --help *> $null; $accHasPrefetch = ($LASTEXITCODE -eq 0) } catch { $accHasPrefetch = $false }
  if ($accHasPrefetch) { $PrefetchExe = $Acc; $PrefetchLead = @('prefetch'); $PrefetchDisplay = 'acc prefetch' }
}
if ((-not $script:ModelId) -or (-not $PrefetchExe)) {
  Emit-Phase 'model_prefetch' 'skipped' ("no model to prefetch for tier=$script:Tier (or no prefetch path: on-disk $PrefetchScript absent and the binary has no prefetch subcommand)") 'phase 7: substrate'
} elseif ($DryRun) {
  # Dry-run honesty: expected size (static, NO network) + the free-disk verdict only.
  if ($script:DiskFreeMb -gt 0) {
    $diskVerdict = 'fits'
    if ($NeedMb -gt $script:DiskFreeMb) { $diskVerdict = 'SHORT -- the disk floor would have degraded the tier in phase 0' }
    Say ("disk verdict: need ~$(MbToGb $NeedMb)GB (model ~$(MbToGb $ExpMb)GB + 2GB headroom), have ~$(MbToGb $script:DiskFreeMb)GB free at $($script:HfCache) -> $diskVerdict")
  } else {
    Say ("disk verdict: free disk unknown at $($script:HfCache) (PSDrive probe failed) -- floor not applied")
  }
  Say ("WOULD: $PrefetchDisplay $script:ModelId (snapshot_download: resume + cache reuse, live progress on stderr; ~$(MbToGb $ExpMb)GB expected -- static approximation, no network in dry-run)")
  Emit-Phase 'model_prefetch' 'would' ("prefetch $script:ModelId (~$(MbToGb $ExpMb)GB) into the HF cache with live progress") 'phase 7: substrate'
} elseif (-not (Have 'uv')) {
  Emit-Phase 'model_prefetch' 'skipped' 'uv not on PATH -- prefetch unavailable' 're-run, or let the daemon download lazily on first start'
} else {
  Say ("prefetching $script:ModelId (~$(MbToGb $ExpMb)GB expected; resume + cache reuse -- a cache hit is instant)...")
  # stdout (the final JSON line) is captured; stderr (live progress) streams through.
  $prefetchOk = $false; $prefetchOut = $null
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    $prefetchOut = & $PrefetchExe @PrefetchLead $script:ModelId
    $prefetchOk = ($LASTEXITCODE -eq 0)
  } catch { $prefetchOk = $false }
  finally { $ErrorActionPreference = $prev }
  if ($prefetchOk) {
    $prefetchNote = 'cached (size unreadable)'
    try {
      $lastLine = ('' + ($prefetchOut | Select-Object -Last 1)).Trim()
      $pj = $lastLine | ConvertFrom-Json
      $prefetchNote = ('{0}GB cached at {1}' -f ([math]::Round($pj.cached_bytes / 1e9, 1)).ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture), $pj.path)
    } catch { $prefetchNote = 'cached (size unreadable)' }
    Emit-Phase 'model_prefetch' 'ok' ("model $script:ModelId prefetched -- $prefetchNote") 'phase 7: substrate'
  } else {
    Emit-Phase 'model_prefetch' 'skipped' 'prefetch failed (network unreachable, or the model is gated) -- the daemon still downloads lazily on first start' 're-run, or let the daemon download lazily on first start'
  }
}

# =========================================================================================
# PHASE 7 -- substrate: ensure the db exists (idempotent; NEVER clobbered). A fresh db is
# created by the first open; we touch it via `acc status` exactly like install.sh.
# =========================================================================================
Step 'phase 7 -- substrate init'
if (Test-Path $DbPath) {
  Emit-Phase 'substrate' 'ok' ("substrate exists at $DbPath (preserved -- never clobbered)")
} elseif ($DryRun) {
  Emit-Phase 'substrate' 'would' ("create a fresh substrate at $DbPath") 'phase 8: config home'
} elseif (-not $BinaryAvailable) {
  Emit-Phase 'substrate' 'skipped' ("substrate init requires the acc binary -- $EnginePendingNote") ("later: acc --db $DbPath status (created on first use)")
} else {
  $r = Invoke-Native $Acc @('--db', $DbPath, 'status')
  if ($r.ok) {
    Emit-Phase 'substrate' 'ok' ("substrate initialized at $DbPath")
  } else {
    Emit-Phase 'substrate' 'skipped' 'could not init substrate (created on first ingest)' ("acc --db $DbPath ingest hello `"hi`"")
  }
}

# =========================================================================================
# PHASE 8 -- config home + daemon endpoint contract (windows-specific). Creates
# %APPDATA%\acc (auth store home -- src/brain.rs default_auth_path) and
# %LOCALAPPDATA%\acc\run (caches + daemon endpoint). Writes run\endpoint.json declaring
# the TCP-loopback+token contract: the daemon publishes embedder.port + embedder.token
# there; clients connect 127.0.0.1:<port> with the token (NO unix sockets on windows).
# engine_lane records honestly whether the engine is live yet.
# =========================================================================================
Step 'phase 8 -- config home + daemon endpoint contract (%APPDATA% / %LOCALAPPDATA%)'
$EngineLane = 'pending'; if ($BinaryAvailable) { $EngineLane = 'live' }
$EndpointObj = [pscustomobject][ordered]@{
  schema      = 'acc.endpoint.v1'
  transport   = 'tcp-loopback'
  host        = '127.0.0.1'
  port_file   = $EmbPortFile
  token_file  = $EmbTokenFile
  engine_lane = $EngineLane
}
$EndpointJson = ConvertTo-Json -InputObject $EndpointObj
$EndpointCurrent = ''
if (Test-Path $EndpointConfig) { try { $EndpointCurrent = (Get-Content $EndpointConfig -Raw).Trim() } catch { $EndpointCurrent = '' } }
if ($EndpointCurrent -eq $EndpointJson.Trim()) {
  Emit-Phase 'config_home' 'ok' ("config home ready: $ConfigHome (auth store) + $RunDir (endpoint: tcp-loopback+token, engine_lane=$EngineLane) -- already declared, unchanged")
} elseif ($DryRun) {
  Emit-Phase 'config_home' 'would' ("create $ConfigHome (auth store home) + $RunDir; write endpoint.json (tcp-loopback 127.0.0.1, port file embedder.port + token file embedder.token, engine_lane=$EngineLane)") 'phase 9: embedder daemon'
} else {
  $wrote = Act 'create config/cache/run dirs + write endpoint.json' {
    foreach ($d in @($ConfigHome, $CacheHome, $RunDir)) {
      if (-not (Test-Path $d)) { $null = New-Item -ItemType Directory -Path $d -Force }
    }
    [IO.File]::WriteAllText($EndpointConfig, $EndpointJson + "`n")
  }
  if ($wrote) {
    $note = ''
    if ($EngineLane -eq 'pending') { $note = ' (engine_lane=pending: the daemon will mint embedder.port + embedder.token here once the windows engine port lands)' }
    Emit-Phase 'config_home' 'ok' ("config home ready: $ConfigHome (auth store, brain.rs contract) + $RunDir; endpoint.json declares tcp-loopback+token$note") 'phase 9: embedder daemon'
  } else {
    Emit-Phase 'config_home' 'failed' 'could not create config home / write endpoint.json' ("create $RunDir manually, then re-run .\install.ps1")
  }
}

# =========================================================================================
# PHASE 9 -- warm embedder daemon. A connect-check LIES about warmth (the daemon binds
# BEFORE the model loads) -- truth = one real token-authenticated encode round-trip over
# 127.0.0.1:<port> (the endpoint contract above) with a short timeout. The model itself
# was prefetched in phase 6, so the first warm-up no longer hides a multi-GB download.
# ENGINE HONESTY: detect-and-report; never fake a running daemon.
# =========================================================================================
function Test-EmbedderWarm {
  if (-not ((Test-Path $EmbPortFile) -and (Test-Path $EmbTokenFile))) { return $false }
  try {
    $port = [int]((Get-Content $EmbPortFile -Raw).Trim())
    $token = (Get-Content $EmbTokenFile -Raw).Trim()
    if ($port -le 0) { return $false }
    $client = New-Object System.Net.Sockets.TcpClient
    try {
      $iar = $client.BeginConnect('127.0.0.1', $port, $null, $null)
      if (-not $iar.AsyncWaitHandle.WaitOne(3000)) { return $false }
      $client.EndConnect($iar)
      $stream = $client.GetStream()
      $stream.ReadTimeout = 3000; $stream.WriteTimeout = 3000
      $req = (ConvertTo-Json -InputObject @{ token = $token; text = 'warm?'; q = $true } -Compress) + "`n"
      $bytes = [Text.Encoding]::UTF8.GetBytes($req)
      $stream.Write($bytes, 0, $bytes.Length)
      $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8)
      $line = $reader.ReadLine()
      if (-not $line) { return $false }
      $resp = $line | ConvertFrom-Json
      return [bool]($resp.PSObject.Properties['vectors'] -and $resp.vectors)
    } finally { $client.Close() }
  } catch { return $false }
}
Step 'phase 9 -- warm embedder daemon (tcp-loopback + token)'
if (Test-EmbedderWarm) {
  Emit-Phase 'embedder_daemon' 'ok' ("embedder already warm on 127.0.0.1 (port/token from $RunDir)")
} elseif ($DryRun) {
  Emit-Phase 'embedder_daemon' 'would' ("start the embedder daemon (model $script:ModelId on $script:Device; first run downloads weights -- several GB); it publishes embedder.port + embedder.token under $RunDir") 'phase 10: browser'
} elseif (-not $BinaryAvailable) {
  Emit-Phase 'embedder_daemon' 'skipped' ("daemon start requires the acc binary -- $EnginePendingNote") 'after the port lands: acc embedder (publishes port+token, loads the model in background)'
} else {
  $script:EmbProc = $null
  $started = Act 'start the embedder daemon (model loads in background)' {
    $script:EmbProc = Start-Process -FilePath $Acc -ArgumentList 'embedder' -RedirectStandardOutput $EmbLogOut -RedirectStandardError $EmbLogErr -PassThru -WindowStyle Hidden
  }
  if ($started) {
    Start-Sleep -Seconds 2
    $alive = $false
    try { $alive = ($null -ne $script:EmbProc) -and (-not $script:EmbProc.HasExited) } catch { $alive = $false }
    if ($alive) {
      Emit-Phase 'embedder_daemon' 'ok' ("embedder starting -- model loads in background (first run downloads it). Log: $EmbLogOut") 'phase 10: browser'
    } else {
      # The native-windows embedder engine IS live in this build (platform/windows.rs +
      # local_ipc.rs TCP-loopback lane). A daemon that exits within 2s is a REAL failure
      # (model load crash, missing CUDA/driver, import error) -- NOT an unfinished lane.
      # Surface it as a failure with the error log + concrete recovery, never a soft hedge.
      $errTail = ''
      if (Test-Path $EmbLogErr) {
        try { $errTail = ((Get-Content $EmbLogErr -Tail 3 -ErrorAction SilentlyContinue) -join ' | ') } catch { $errTail = '' }
      }
      $det = "embedder daemon exited within 2s -- a real start failure (model load / CUDA-driver / import error), not a pending lane. Log: $EmbLogErr"
      if ($errTail) { $det = "$det -- last: $errTail" }
      Emit-Phase 'embedder_daemon' 'failed' $det ("read the error above + $EmbLogErr, fix the cause, then: acc embedder  (or use the container: docs/INSTALL_CONTAINER.md)")
    }
  } else {
    Emit-Phase 'embedder_daemon' 'skipped' 'could not start the embedder daemon' ("manually: acc embedder (log: $EmbLogOut)")
  }
}

# =========================================================================================
# PHASE 10 -- browser capability (Camoufox, host-side). Optional only when ACC_NO_BROWSER=1.
# Mirrors install.sh's browser accelerator, with native Windows virtualenv paths. The binary
# owns broker.py restore + daemon convergence at point of use; the installer provisions the
# Python env and fetches the Camoufox browser so first browser use is ready.
# =========================================================================================
Step 'phase 10 -- browser capability (Camoufox)'
function Get-BrowserCamoufox {
  foreach ($name in @('camoufox.exe', 'camoufox.cmd', 'camoufox')) {
    $p = Join-Path $BrowserScripts $name
    if (Test-Path $p) { return $p }
  }
  return (Join-Path $BrowserScripts 'camoufox.exe')
}
function Test-BrowserVenvReady {
  return ((Test-Path $BrowserPython) -and (Test-Path (Get-BrowserCamoufox)))
}
if ($NoBrowser) {
  Emit-Phase 'browser' 'skipped' 'ACC_NO_BROWSER=1 -- browser capability skipped'
} elseif (Test-BrowserVenvReady) {
  Emit-Phase 'browser' 'ok' ("browser venv already provisioned at $BrowserVenv")
} elseif ($DryRun) {
  Emit-Phase 'browser' 'would' ("create browser venv at $BrowserVenv; install camoufox+playwright; fetch Camoufox") 'phase 11: seed'
} elseif (-not (Have 'uv')) {
  Emit-Phase 'browser' 'failed' 'uv not on PATH -- cannot provision the Camoufox browser env' 're-run phase 1 or install uv from https://astral.sh/uv'
} else {
  $browserOk = $true
  $browserOk = $browserOk -and (Act 'create browser dirs' {
    foreach ($d in @($BrowserHome, $BrowserProfiles)) {
      if (-not (Test-Path $d)) { $null = New-Item -ItemType Directory -Path $d -Force }
    }
  })
  if (-not (Test-Path $BrowserPython)) {
    $browserOk = $browserOk -and (Act ("create browser venv at $BrowserVenv") {
      $r = Invoke-NativeChatter 'uv' @('venv', $BrowserVenv)
      if (-not $r) { throw 'uv venv reported an issue' }
    })
  }
  $browserOk = $browserOk -and (Act 'install camoufox + playwright into the browser venv' {
    $r = Invoke-NativeChatter 'uv' @('pip', 'install', '--python', $BrowserPython, '-q', 'camoufox', 'playwright')
    if (-not $r) { throw 'uv pip install camoufox playwright reported an issue' }
  })
  $browserOk = $browserOk -and (Act 'fetch Camoufox browser (idempotent)' {
    $cf = Get-BrowserCamoufox
    $r = Invoke-NativeChatter $cf @('fetch')
    if (-not $r) { throw 'camoufox fetch reported an issue' }
  })
  if ($browserOk -and (Test-BrowserVenvReady)) {
    Emit-Phase 'browser' 'ok' ("Camoufox browser ready at $BrowserHome (daemon + runtime:browser seeded in phase 11)") 'phase 11: seed'
  } else {
    Emit-Phase 'browser' 'failed' 'Camoufox browser provisioning did not complete' ("re-run .\install.ps1; or: uv pip install --python $BrowserPython camoufox playwright; $(Get-BrowserCamoufox) fetch")
  }
}

# =========================================================================================
# PHASE 11 -- seed core runtimes (waits for the embedder to warm -- seeding encodes with
# the REAL embedder). Browser convergence (`acc browser start`) runs once the embedder is
# warm, restoring broker.py, starting the broker, and seeding runtime:browser. The embedder
# warm-wait mirrors install.sh's 600s loop over the tcp-loopback+token round-trip.
# =========================================================================================
Step 'phase 11 -- seed core runtimes (waits for the embedder)'
if ($DryRun) {
  Emit-Phase 'seed' 'would' 'wait for the embedder to warm, then converge the Camoufox browser daemon + seed runtime:browser' 'phase 12: wiring'
} elseif (-not $BinaryAvailable) {
  Emit-Phase 'seed' 'skipped' ("seeding requires the acc binary + warm embedder -- $EnginePendingNote") 'after the port lands: re-run .\install.ps1'
} elseif ($NonInteractive) {
  # NON-INTERACTIVE (output redirected / captured / -NonInteractive / ACC_NONINTERACTIVE=1):
  # the 600s warm-wait below hides the multi-GB first-run model download inside a synchronous
  # loop -- an agent's command TIMEOUT kills the install mid-wait, leaving a half-state and
  # never printing the next step. The critical path (binary, .mcp.json, hooks) runs in the
  # phases AFTER this one; the embedder warms in the BACKGROUND on its own. SKIP the wait, name
  # the background warm + how to check it, and let the remaining phases run so the script exits
  # promptly. ($warm stays $false -> the final block prints the honest "warming in background".)
  $warm = $false
  $embDied = $false
  Emit-Phase 'seed' 'skipped' ("non-interactive install: not blocking on the embedder warm-up (your Work Model warms up in the background -- downloading the model, several GB on first run). Check progress in a few minutes with: acc --db $DbPath doctor") ("acc --db $DbPath browser start (after the model finishes loading)")
} else {
  Say 'waiting for the embedder (first run may download the model -- several GB, takes minutes)...'
  $warm = $false
  $embDied = $false
  for ($i = 0; $i -lt 600; $i++) {
    if (Test-EmbedderWarm) { $warm = $true; break }
    # FAIL-FAST BAIL (a): the daemon process EXITED. A crash-on-start (model load failure,
    # missing CUDA/driver, import error) would otherwise burn the full 600s printing
    # 'may still be downloading' then a bare timeout. Mirror install.sh:990 -- if the
    # embedder process we started is gone, the daemon EXITED; stop waiting now.
    if (($null -ne $script:EmbProc) -and ($script:EmbProc.HasExited)) {
      $embDied = $true
      Say '[embedder] daemon process exited -- see the log'
      break
    }
    # FAIL-FAST BAIL (b): permanent-failure scan. The daemon is a SUPERVISOR that respawns a
    # crash-looping worker, so the HasExited check above never fires on a hard ImportError /
    # bad-model load -- the worker dies, the daemon lives, and the loop burns the full 600s.
    # Scan the embedder log for a TERMINAL signature (none are transient-download messages)
    # and bail NOW. Mirrors install.sh:1002-1007 (same signature set: src subproc_encoder.rs:505
    # emits 'WORKER CRASH-LOOP -- ... refusing respawns').
    if ($i -ge 3) {
      $sig = 'ImportError|cannot import name|WARMUP FAILED|serve failed|WORKER CRASH-LOOP|refusing respawn'
      foreach ($log in @($EmbLogErr, $EmbLogOut)) {
        if ($embDied) { break }
        if (Test-Path $log) {
          try {
            $hit = Select-String -Path $log -Pattern $sig -Quiet -ErrorAction SilentlyContinue
          } catch { $hit = $false }
          if ($hit) {
            $embDied = $true
            Say "[embedder] hard failure detected in $log -- not waiting out the 10-min clock"
            break
          }
        }
      }
      if ($embDied) { break }
    }
    if ((($i % 10) -eq 0) -and ($i -gt 0)) { Say ("[embedder wait ${i}s/600s] model loading into memory/VRAM (weights pre-fetched; first load takes a moment) (log: $EmbLogOut)") }
    Start-Sleep -Seconds 1
  }
  if ($warm) {
    if ($i -gt 0) { Say ("embedder ready after ~${i}s") }
    if (-not $NoBrowser) {
      $r = Invoke-Native $Acc @('--db', $DbPath, 'browser', 'start')
      if ($r.ok) {
        Emit-Phase 'seed' 'ok' 'converged Camoufox browser daemon + seeded runtime:browser' 'phase 12: wiring'
      } else {
        Emit-Phase 'seed' 'failed' 'browser convergence reported an issue after embedder warm' ("check the broker log, then run: acc --db $DbPath browser start")
      }
    } else {
      Emit-Phase 'seed' 'ok' 'embedder warm (browser skipped)' 'phase 12: wiring'
    }
  } else {
    # On EITHER an early exit (the daemon/worker crashed) OR the 600s timeout, tail the
    # embedder logs so the real CUDA/driver/import error surfaces instead of a bare
    # 'did not warm'. The native-windows embedder engine IS live in this build, so a
    # non-warm embedder is a REAL failure -- give the actual error + concrete recovery,
    # never a 'lane may be pending' hedge. Mirrors install.sh:1019-1033.
    foreach ($log in @($EmbLogErr, $EmbLogOut)) {
      if (Test-Path $log) {
        Say ("-- last lines of $log --")
        try { (Get-Content $log -Tail 20 -ErrorAction SilentlyContinue) | ForEach-Object { Say ("  $_") } } catch { }
      }
    }
    if ($embDied) {
      Emit-Phase 'seed' 'failed' ("embedder daemon/worker crashed before warming (see the log tail above + $EmbLogErr -- likely model-load / CUDA-driver / import error)") ("fix the error above, then: acc embedder  ;  acc --db $DbPath browser start  (or use the container: docs/INSTALL_CONTAINER.md)")
    } else {
      Emit-Phase 'seed' 'failed' ("embedder did not warm within 10min (see the log tail above + $EmbLogOut) -- a real stall, not a pending lane") ("inspect the log; once it loads run: acc --db $DbPath browser start  (or use the container: docs/INSTALL_CONTAINER.md)")
    }
  }
}

# =========================================================================================
# PHASE 12 -- wiring: register acc as an MCP server (project-local .mcp.json) EXACTLY the
# way install.sh phase 11 does: relative "acc.db" on purpose (Claude Code launches MCP
# servers from the project dir -- clone-portable). "alwaysLoad": true skips MCP tool-search
# deferral (the two verbs are the kernel interface -- never lazy-loaded). Idempotent: a
# complete acc entry (with alwaysLoad) is left unchanged; a pre-alwaysLoad entry is upgraded
# IN PLACE (the key is added, every other mcpServers key preserved). User-level settings
# under %USERPROFILE%\.claude are NOT touched -- the wiring is project-local, same as install.sh.
# =========================================================================================
Step 'phase 12 -- register acc as an MCP server (.mcp.json)'
$McpPath = Join-Path $Repo '.mcp.json'
function Test-McpHasAccAlwaysLoad {
  if (-not (Test-Path $McpPath)) { return $false }
  try {
    $d = Get-Content $McpPath -Raw | ConvertFrom-Json
    if (-not (($d.PSObject.Properties['mcpServers']) -and ($d.mcpServers.PSObject.Properties['acc']))) { return $false }
    $e = $d.mcpServers.acc
    return [bool](($e.PSObject.Properties['alwaysLoad']) -and ($e.alwaysLoad -eq $true))
  } catch { return $false }
}
if ($RepoIsClone) {
  # The clone dir is NOT a project the user opens -- wiring .mcp.json there is dead config
  # (Claude Code launches MCP servers from the dir the user OPENS, never the hidden clone).
  # The one-Work-Model pivot: Claude Code is wired GLOBALLY in phase 14 (`acc hosts-sync`
  # registers ~/.claude.json mcpServers.acc on the ONE global db), so NO per-project step is
  # needed -- acc works in every directory the moment phase 14 runs. Honest skip here.
  Emit-Phase 'mcp_wiring' 'skipped' ("global install -- not wiring .mcp.json into the hidden clone dir ($Repo). Claude Code is wired GLOBALLY in phase 14 (acc hosts-sync -> ~/.claude.json, one global Work Model) -- no per-project step needed.") 'phase 14 wires Claude Code globally (acc hosts-sync)'
} elseif ($DryRun) {
  if (Test-McpHasAccAlwaysLoad) {
    Emit-Phase 'mcp_wiring' 'ok' '.mcp.json already registers the acc server with alwaysLoad (would leave unchanged)'
  } else {
    Emit-Phase 'mcp_wiring' 'would' 'write project-local .mcp.json (server: acc - db: acc.db, relative - alwaysLoad: true)' 'phase 13: hooks'
  }
} else {
  $mcpDetail = ''; $mcpStatus = 'ok'
  $mcpData = $null; $mcpParseFailed = $false
  if (Test-Path $McpPath) {
    try { $mcpData = Get-Content $McpPath -Raw | ConvertFrom-Json }
    catch { $mcpParseFailed = $true }
  }
  if ($mcpParseFailed) {
    $mcpStatus = 'skipped'; $mcpDetail = '.mcp.json exists but is not valid JSON -- fix it or paste the acc entry manually'
    Emit-Phase 'mcp_wiring' $mcpStatus $mcpDetail 'edit .mcp.json by hand or re-run'
  } else {
    if ($null -eq $mcpData) { $mcpData = [pscustomobject]@{} }
    if (-not ($mcpData.PSObject.Properties['mcpServers'])) {
      $mcpData | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue ([pscustomobject]@{})
    }
    if ($mcpData.mcpServers.PSObject.Properties['acc']) {
      $existing = $mcpData.mcpServers.acc
      if (($existing.PSObject.Properties['alwaysLoad']) -and ($existing.alwaysLoad -eq $true)) {
        $mcpDetail = '.mcp.json already has a complete acc entry (alwaysLoad: true) -- left unchanged'
      } else {
        # Upgrade IN PLACE: add alwaysLoad=$true (a JSON boolean via ConvertTo-Json -- not the
        # string 'True'), preserving every other acc + mcpServers key on the parsed object.
        if ($existing.PSObject.Properties['alwaysLoad']) {
          $existing.alwaysLoad = $true
        } else {
          $existing | Add-Member -NotePropertyName 'alwaysLoad' -NotePropertyValue $true
        }
        [IO.File]::WriteAllText($McpPath, (ConvertTo-Json -InputObject $mcpData -Depth 16) + "`n")
        $mcpDetail = 'upgraded .mcp.json acc entry in place -- added alwaysLoad: true (rest preserved)'
      }
    } else {
      $entry = [pscustomobject][ordered]@{ command = 'acc'; args = @('--db', 'acc.db', 'mcp'); alwaysLoad = $true }
      $mcpData.mcpServers | Add-Member -NotePropertyName 'acc' -NotePropertyValue $entry
      [IO.File]::WriteAllText($McpPath, (ConvertTo-Json -InputObject $mcpData -Depth 16) + "`n")
      $mcpDetail = 'wrote project-local .mcp.json (server: acc - db: acc.db, relative on purpose - alwaysLoad: true)'
    }
    Emit-Phase 'mcp_wiring' $mcpStatus $mcpDetail 'phase 13: hooks'
  }
}

# =========================================================================================
# PHASE 13 -- hooks: register acc's Claude Code hooks via `acc hooks-wire $Repo` (mirror of
# install.sh phase 11b). The eight-event lifecycle is wired by the BINARY -- the registrations
# are direct `acc hook <verb> --host claude-code` invocations COMPILED INTO acc
# (src/hookwire.rs ACC_HOOK_REGISTRATIONS), NOT POSIX shell scripts -- so there is NO bash /
# Git-for-Windows dependency on native windows. The merge is ADD-ONLY (a pre-existing non-acc
# hook is preserved), IDEMPOTENT, and DEV-CLONE-AWARE: a git-tracked .claude/settings.json
# (this repo) is left UNCHANGED so the install creates no spurious diffs. Needs the built
# binary -- degrades with the pending note until the windows engine port lands.
# =========================================================================================
Step 'phase 13 -- register acc''s Claude Code hooks (.claude/settings.json)'
$SettingsPath = Join-Path (Join-Path $Repo '.claude') 'settings.json'
if ($RepoIsClone) {
  # Same as phase 12: the hidden clone is not a project the user opens, so wiring its
  # .claude\settings.json is dead. The one-Work-Model pivot: phase 14 (`acc hosts-sync`) now
  # writes acc's hooks GLOBALLY into ~/.claude/settings.json (the user settings), so the hooks
  # fire in every directory -- no per-project step. Honest skip; phase 14 does it.
  Emit-Phase 'hooks_wiring' 'skipped' ("global install -- not wiring .claude\settings.json into the hidden clone dir ($Repo). Claude Code hooks are wired GLOBALLY in phase 14 (acc hosts-sync -> ~/.claude/settings.json) -- no per-project step needed.") 'phase 14 wires Claude Code globally (acc hosts-sync)'
} elseif (-not $BinaryAvailable) {
  Emit-Phase 'hooks_wiring' 'skipped' ("hooks-wire requires the acc binary -- $EnginePendingNote") 'after the engine port lands: acc hooks-wire'
} elseif ($DryRun) {
  # Dry-run: report the would-action WITHOUT writing. On the dev clone (tracked settings.json)
  # the subcommand is a no-op; a tracked or already-wired file reports KEPT honestly.
  $tracked = $false
  if (Test-Path $SettingsPath) {
    $g = Invoke-Native 'git' @('-C', $Repo, 'ls-files', '--error-unmatch', '.claude/settings.json')
    $tracked = $g.ok
  }
  $hasAccHook = $false
  if ((Test-Path $SettingsPath) -and -not $tracked) {
    try { if ((Get-Content $SettingsPath -Raw) -match 'acc hook ') { $hasAccHook = $true } } catch { }
  }
  if ($tracked) {
    Emit-Phase 'hooks_wiring' 'ok' '.claude/settings.json is git-tracked (dev clone) -- would leave unchanged (the clone ships the wiring; rewriting it would create spurious diffs)' 'phase 14: hosts-sync'
  } elseif ($hasAccHook) {
    Emit-Phase 'hooks_wiring' 'ok' '.claude/settings.json already registers acc''s hooks (would leave unchanged)' 'phase 14: hosts-sync'
  } else {
    Emit-Phase 'hooks_wiring' 'would' 'register acc''s eight-event hook lifecycle into .claude/settings.json (add-only; cold-start briefing - prompt grounding - Stop guard)' 'phase 14: hosts-sync'
  }
} else {
  $r = Invoke-Native $Acc @('hooks-wire', $Repo)
  $hooksOut = ('' + (($r.out | Out-String).Trim()))
  if ($r.ok -and ($hooksOut -match '^(WROTE|MERGED|KEPT)')) {
    Emit-Phase 'hooks_wiring' 'ok' $hooksOut 'phase 14: hosts-sync'
  } else {
    $detail = if ($hooksOut) { "acc hooks-wire reported an issue: $hooksOut (fail-soft -- re-run: acc hooks-wire)" } else { 'acc hooks-wire reported an issue (fail-soft -- re-run: acc hooks-wire)' }
    Emit-Phase 'hooks_wiring' 'skipped' $detail 'acc hooks-wire'
  }
}

# =========================================================================================
# PHASE 14 -- host wiring: `acc hosts-sync` converges EVERY coding agent installed on this
# machine onto the ONE global substrate -- the one-Work-Model pivot. ALL FOUR agents wire
# GLOBALLY here: Claude Code (user-scope ~/.claude.json mcpServers.acc + ~/.claude/settings.json
# hooks, on the canonical global db), OpenCode, Codex CLI, Cursor -- each two-verb MCP +
# lifecycle recording, ADD-ONLY (an existing acc entry is never rewritten), one backup per
# changed file. A fresh install leaves all agents on one compounding memory with NO per-project
# step. Fail-soft: wiring an agent is convenience -- it NEVER fails the install. Honors -DryRun
# (preview, nothing written) and ACC_HOSTS_SYNC=off (escape -> skip). The optional isolation
# override is `acc hosts-sync --project .`. Mirror of install.sh phase 13. Needs the built
# binary -- skips with the pending note until then.
# =========================================================================================
Step 'phase 14 -- wire installed coding agents globally (acc hosts-sync)'
if (-not $BinaryAvailable) {
  Emit-Phase 'hosts_sync' 'skipped' ("hosts-sync requires the acc binary -- $EnginePendingNote") 'after the engine port lands: acc hosts-sync'
} elseif ($env:ACC_HOSTS_SYNC -eq 'off') {
  Emit-Phase 'hosts_sync' 'skipped' 'ACC_HOSTS_SYNC=off -- sibling-host convergence skipped by request' 'unset ACC_HOSTS_SYNC and re-run, or: acc hosts-sync'
} elseif ($DryRun) {
  $r = Invoke-Native $Acc @('hosts-sync', '--dry-run')
  foreach ($line in @($r.out)) { $l = ('' + $line).Trim(); if ($l) { Say $l } }
  Emit-Phase 'hosts_sync' 'would' 'converge installed coding agents (preview above -- add-only; nothing written in dry-run)' 'phase 15: telemetry'
} else {
  $r = Invoke-Native $Acc @('hosts-sync')
  foreach ($line in @($r.out)) { $l = ('' + $line).Trim(); if ($l) { Say $l } }
  if ($r.ok) {
    Emit-Phase 'hosts_sync' 'ok' 'installed coding agents converged (per-host lines above; re-run acc hosts-sync after installing a new agent)' 'phase 15: telemetry'
  } else {
    Emit-Phase 'hosts_sync' 'skipped' 'acc hosts-sync reported an issue (fail-soft -- host wiring never blocks an install)' 'acc hosts-sync'
  }
}

# =========================================================================================
# PHASE 15 -- telemetry (anonymous usage events, ON by default). Mirror of install.sh phase
# 15 / parity with the POSIX installer. The PostHog token is the project's WRITE-ONLY
# ingestion key -- public-safe by design (it can only append events, never read). Events are
# NAMES ONLY -- never owner data, prompts, files, or memory. On by default so the maintainer
# can see what breaks for real users; opt out any time with `acc telemetry off`, or set
# ACC_NO_TELEMETRY=1 before install to never enable it. Fail-soft: a CLI error never fails
# the install. Needs the built binary -- without it (windows engine port pending) we skip
# with an honest note.
#
# KEY SOURCE: parsed at runtime from the SAME `TELEMETRY_KEY=` line in install.sh next to this
# script ($PSScriptRoot) -- ONE canonical home for the key (install.sh) so the two installers
# can never drift to different keys, and the lone secret-shaped token lives in exactly one file.
# =========================================================================================
$TelemetryKey = ''
try {
  $InstallSh = Join-Path $PSScriptRoot 'install.sh'
  if (Test-Path $InstallSh) {
    $m = Select-String -Path $InstallSh -Pattern 'TELEMETRY_KEY="([^"]+)"' | Select-Object -First 1
    if ($m) { $TelemetryKey = $m.Matches[0].Groups[1].Value }
  }
} catch { $TelemetryKey = '' }

Step 'phase 15 -- telemetry (anonymous usage events, on by default)'
if ($DryRun) {
  Emit-Phase 'telemetry' 'would' 'enable anonymous usage telemetry by default (event names only -- never your data, prompts, files, or Work Model; opt-out: acc telemetry off)' 'phase 16: verify'
} elseif ($env:ACC_NO_TELEMETRY -eq '1') {
  Emit-Phase 'telemetry' 'skipped' 'ACC_NO_TELEMETRY=1 -- telemetry stays off' 'enable later: acc telemetry on --key <your key> --host us'
} elseif (-not $TelemetryKey) {
  Emit-Phase 'telemetry' 'skipped' 'could not read the telemetry key from install.sh (non-fatal)' 'enable later: acc telemetry on --key <your key> --host us'
} elseif ($BinaryAvailable) {
  try {
    & $Acc telemetry on --key $TelemetryKey --host us *> $null
    if ($LASTEXITCODE -eq 0) {
      # One real event: `telemetry status` runs the app_opened instrumentation, queued through
      # the normal pipeline (no custom capture path here).
      & $Acc telemetry status *> $null
      Emit-Phase 'telemetry' 'ok' 'anonymous usage telemetry ON (event names only -- never your data, prompts, files, or Work Model). opt out: acc telemetry off' 'phase 16: verify'
    } else {
      Emit-Phase 'telemetry' 'skipped' 'could not enable telemetry (non-fatal)' 'enable later: acc telemetry on --key <your key> --host us'
    }
  } catch {
    Emit-Phase 'telemetry' 'skipped' 'could not enable telemetry (non-fatal)' 'enable later: acc telemetry on --key <your key> --host us'
  }
} else {
  Emit-Phase 'telemetry' 'skipped' "telemetry requires the acc binary ($EnginePendingNote)" 'enable later: acc telemetry on'
}

# =========================================================================================
# PHASE 16 -- verify: `acc doctor` (the end-to-end self-check). In -Json mode the final
# stream line is the verdict + the `acc doctor --json` handoff for Claude-as-installer.
# ENGINE HONESTY: without the built binary there is NO doctor -- reported, never faked.
# =========================================================================================
Step 'phase 16 -- verify (acc doctor)'
if ($DryRun) {
  Emit-Phase 'verify' 'would' ("run: acc --db $DbPath doctor (proves binary/substrate/embedder/model_pin/sandbox/mcp/hooks/brain)") ("acc --db $DbPath doctor --json")
} elseif (-not $BinaryAvailable) {
  Emit-Phase 'verify' 'skipped' ("acc doctor unavailable -- $EnginePendingNote") 're-run .\install.ps1 after the engine port lands for the doctor handoff'
} else {
  if ($Json) {
    $r = Invoke-Native $Acc @('--db', $DbPath, 'doctor', '--json')
    $docStatus = 'unknown'
    if ($r.out) {
      try { $docStatus = '' + ((($r.out | Out-String).Trim()) | ConvertFrom-Json).status } catch { $docStatus = 'unknown' }
    }
    if ($docStatus -eq 'ok') {
      Emit-Phase 'verify' 'ok' ("acc doctor: $docStatus") ("acc --db $DbPath doctor --json")
    } else {
      Emit-Phase 'verify' 'ok' ("acc doctor: $docStatus (degraded layers are normal on a fresh install -- see the doctor report)") ("acc --db $DbPath doctor --json")
    }
  } else {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & $Acc --db $DbPath doctor } catch { }
    finally { $ErrorActionPreference = $prev }
  }
}

# -- final verdict ------------------------------------------------------------------------
if ($Json) {
  if ($DryRun) {
    Emit-Phase 'verdict' 'would' ("dry-run complete: all phases walked, nothing mutated; tier=$script:Tier ($script:ModelId on $script:Device)") 'run .\install.ps1 (no -DryRun) to install'
  } elseif ($script:AnyFailed) {
    Emit-Phase 'verdict' 'failed' ("install degraded: a phase failed -- on windows this usually means the engine port is still in flight (config + wiring landed; binary-dependent phases reported honestly)") ("acc --db $DbPath doctor --json (after the engine windows lane lands)")
  } else {
    Emit-Phase 'verdict' 'ok' ("install complete; tier=$script:Tier ($script:ModelId on $script:Device). Verify with the doctor handoff.") ("acc --db $DbPath doctor --json")
  }
  if ($script:AnyFailed -and (-not $DryRun)) { exit 1 }
  exit 0
}

Step 'done'
if ($DryRun) {
  Ok 'dry-run complete -- all phases walked, NOTHING mutated.'
  Say ("Selected tier: $script:Tier - $script:ModelId on $script:Device")
  Say 'Run .\install.ps1 (no -DryRun) to install for real.'
  exit 0
}
if ($script:AnyFailed) {
  Warn 'install finished DEGRADED -- a phase failed (on windows this usually means the engine port is still in flight; config + Claude Code wiring landed).'
  Say 'Re-run .\install.ps1 once the acc windows engine lane lands; each phase resumes from its postcondition.'
  exit 1
}

# NEXT-STEP guidance. The one-Work-Model pivot: phase 14 wired ALL agents (Claude Code,
# OpenCode, Codex, Cursor) GLOBALLY onto ONE compounding memory -- they work in EVERY
# directory now, no per-project step. So the next step is simply: open Claude Code anywhere
# and talk. The OPTIONAL isolation override (`acc hosts-sync --project .`) carves a project
# onto its own db. Mirrors install.sh's cc_next_lines.
$CcNext = @"
acc is wired into all your agents (Claude Code, OpenCode, Codex, Cursor) GLOBALLY on ONE Work Model
that compounds across every task and project. Open Claude Code in ANY directory and just say what
you want done in plain words. The two verbs (acc_retrieve + acc_act) appear after a restart / reload
MCP if Claude Code is open.
Optional -- isolate a project on its OWN separate Work Model (confidential / separated work):
  cd <your-project>; acc hosts-sync --project .
The CLI lane works right now with no restart: acc --db $DbPath retrieve "..."  ;  acc --db $DbPath ingest ...
"@

if ($NonInteractive -and (-not $warm)) {
  # NON-INTERACTIVE path: we deliberately SKIPPED the blocking warm-wait (phase 11), so the
  # embedder is warming in the BACKGROUND -- NOT a failure. Print a clear line and exit 0
  # promptly (a captured stdout shows the next step without ever hitting the agent's timeout).
  Ok 'acc installed. Your Work Model is warming up -- downloading the model in the background (several GB on first run).'
  Write-Chatter @"

Check progress in a few minutes:
  acc --db $DbPath doctor        (expect: embedder OK once the model finishes loading)

Once the embedder is warm, retrieval is live. The CLI works immediately:
  acc --db $DbPath ingest hello "acc is live -- the Work Model is recording"
  acc --db $DbPath retrieve "what acc is"   (works once the embedder reports OK above)

$CcNext

There is no login, credential, OAuth, or API key -- ever; the interactive session IS the brain.
"@
  exit 0
}

Ok 'acc install complete.'
Write-Chatter @"

Try these now:
  1. Check health:        acc --db $DbPath doctor
  2. Add one entry:       acc --db $DbPath ingest hello "acc is live -- the Work Model is recording"
  3. Retrieve it:         acc --db $DbPath retrieve "what acc is"

$CcNext

Brain-backed solve works by opening your interactive agent (Claude Code / Codex / OpenCode)
on this project -- the MCP picks it up; the interactive session IS the brain. Work Model
retrieval already works. There is no login, credential, OAuth, or API key -- ever.
"@
exit 0
