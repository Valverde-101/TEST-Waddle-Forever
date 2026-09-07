Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WaddleNodeModulesPath {
  param([Parameter(Mandatory)][string]$WorkRoot)
  return [IO.Path]::GetFullPath((Join-Path $WorkRoot 'dependencies\current\node_modules'))
}

function Enable-WaddleLocalNodeTooling {
  param([Parameter(Mandatory)][string]$WorkRoot)

  $modules = Get-WaddleNodeModulesPath -WorkRoot $WorkRoot
  $bin = [IO.Path]::GetFullPath((Join-Path $modules '.bin'))
  $env:WADDLE_NODE_MODULES = $modules
  $env:NODE_PATH = $modules

  $pathParts = @([string]$env:PATH -split ';' | Where-Object { $_ })
  if (-not ($pathParts | Where-Object { $_.TrimEnd('\') -ieq $bin.TrimEnd('\') })) {
    $env:PATH = "$bin;$env:PATH"
  }

  Write-Host "WADDLE_NODE_TOOLING=PASS modules=$modules bin=$bin"
  [pscustomobject]@{ status='PASS'; modules=$modules; bin=$bin }
}

function Remove-WaddleJunctionOnly {
  param([Parameter(Mandatory)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) { return }
  $item = Get-Item -LiteralPath $Path -Force
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
    throw "WADDLE_JUNCTION_REMOVE=FAIL not_reparse_point=$Path"
  }

  & cmd.exe /d /c "rmdir `"$Path`"" | Out-Null
  if ($LASTEXITCODE -ne 0 -or (Test-Path -LiteralPath $Path)) {
    throw "WADDLE_JUNCTION_REMOVE=FAIL path=$Path exit=$LASTEXITCODE"
  }
  $global:LASTEXITCODE = 0
  Write-Host "WADDLE_JUNCTION_REMOVE=PASS path=$Path"
}

function Install-WaddleDependencies {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$WorkRoot
  )

  Assert-WaddleWindowsOnly
  $target = Get-WaddleNodeModulesPath -WorkRoot $WorkRoot
  $cache = Join-Path $WorkRoot 'cache\yarn'
  $link = Join-Path $RepoRoot 'node_modules'
  New-Item -ItemType Directory -Force -Path $target,$cache | Out-Null

  if (Test-Path -LiteralPath $link) {
    $item = Get-Item -LiteralPath $link -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      Remove-WaddleJunctionOnly -Path $link
    } else {
      throw "WADDLE_DEPENDENCIES=FAIL node_modules_not_junction=$link"
    }
  }

  $yarn = Get-Command yarn.cmd -ErrorAction Stop
  $env:YARN_CACHE_FOLDER = $cache
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $exit = 1
  Push-Location $RepoRoot
  try {
    & $yarn.Source install --frozen-lockfile --non-interactive --modules-folder $target --cache-folder $cache | Out-Host
    $exit = $LASTEXITCODE
  } finally {
    Pop-Location
    Ensure-WaddleJunction -LinkPath $link -TargetPath $target
  }
  $sw.Stop()

  if ($exit -ne 0) {
    throw "WADDLE_DEPENDENCIES=FAIL exit=$exit duration_ms=$($sw.ElapsedMilliseconds) target=$target"
  }

  $electronManifest = Join-Path $target 'electron\package.json'
  if (-not (Test-Path -LiteralPath $electronManifest -PathType Leaf)) {
    throw "WADDLE_DEPENDENCIES=FAIL electron_missing=$electronManifest"
  }
  $electron = Get-Content -LiteralPath $electronManifest -Raw | ConvertFrom-Json
  if ([string]$electron.version -ne '10.4.7') {
    throw "WADDLE_DEPENDENCIES=FAIL electron_contract expected=10.4.7 actual=$($electron.version)"
  }

  Enable-WaddleLocalNodeTooling -WorkRoot $WorkRoot | Out-Null
  Write-Host "WADDLE_DEPENDENCIES=PASS target=$target cache=$cache electron=$($electron.version) duration_ms=$($sw.ElapsedMilliseconds)"
  [pscustomobject]@{
    status = 'PASS'
    node_modules = $target
    yarn_cache = $cache
    electron = [string]$electron.version
  }
}

function Test-WaddleElectronRuntime {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][string]$ExpectedVersion,
    [int]$ProbeTimeoutMilliseconds = 10000
  )

  Assert-WaddleWindowsOnly
  $modules = Get-WaddleNodeModulesPath -WorkRoot $WorkRoot
  $manifestPath = Join-Path $modules 'electron\package.json'
  $electronExe = [IO.Path]::GetFullPath((Join-Path $modules 'electron\dist\electron.exe'))

  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "WADDLE_ELECTRON_RUNTIME=FAIL manifest_missing=$manifestPath"
  }
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  $manifestVersion = [string]$manifest.version
  if ($manifestVersion -ne $ExpectedVersion -or $manifestVersion -ne '10.4.7') {
    throw "WADDLE_ELECTRON_RUNTIME=FAIL version_mismatch expected=$ExpectedVersion pinned=10.4.7 actual=$manifestVersion"
  }
  if (-not (Test-Path -LiteralPath $electronExe -PathType Leaf)) {
    throw "WADDLE_ELECTRON_RUNTIME=FAIL executable_missing=$electronExe"
  }

  $item = Get-Item -LiteralPath $electronExe -Force
  if ($item.Length -lt 1048576) {
    throw "WADDLE_ELECTRON_RUNTIME=FAIL suspicious_size=$($item.Length) executable=$electronExe"
  }

  $stream = [IO.File]::Open($electronExe,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
  try {
    $mz0 = $stream.ReadByte()
    $mz1 = $stream.ReadByte()
  } finally {
    $stream.Dispose()
  }
  if ($mz0 -ne 0x4D -or $mz1 -ne 0x5A) {
    throw "WADDLE_ELECTRON_RUNTIME=FAIL invalid_pe_signature executable=$electronExe"
  }

  $previousRunAsNode = [Environment]::GetEnvironmentVariable('ELECTRON_RUN_AS_NODE','Process')
  $probe = $null
  try {
    [Environment]::SetEnvironmentVariable('ELECTRON_RUN_AS_NODE','1','Process')
    $probe = Start-Process -FilePath $electronExe -ArgumentList @('-e','process.exit(0)') -WorkingDirectory (Split-Path -Parent $electronExe) -PassThru
    if (-not $probe.WaitForExit($ProbeTimeoutMilliseconds)) {
      try { $probe.Kill() } catch {}
      throw "WADDLE_ELECTRON_RUNTIME=FAIL probe_timeout_ms=$ProbeTimeoutMilliseconds executable=$electronExe"
    }
    $probe.Refresh()
    if ($probe.ExitCode -ne 0) {
      throw "WADDLE_ELECTRON_RUNTIME=FAIL probe_exit=$($probe.ExitCode) executable=$electronExe mode=run_as_node"
    }
  } catch {
    if ($_.Exception.Message -like 'WADDLE_ELECTRON_RUNTIME=FAIL*') { throw }
    throw "WADDLE_ELECTRON_RUNTIME=FAIL process_start executable=$electronExe error=$($_.Exception.Message)"
  } finally {
    if ($null -eq $previousRunAsNode) {
      Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
    } else {
      [Environment]::SetEnvironmentVariable('ELECTRON_RUN_AS_NODE',$previousRunAsNode,'Process')
    }
    if ($probe) { $probe.Dispose() }
  }

  $productVersion = [string]$item.VersionInfo.ProductVersion
  $fileVersion = [string]$item.VersionInfo.FileVersion
  Write-Host "WADDLE_ELECTRON_RUNTIME=PASS version=$manifestVersion executable=$electronExe size=$($item.Length) pe=MZ direct_process_probe=PASS launch_mode=dependency_source product_version=$productVersion file_version=$fileVersion"
  [pscustomobject]@{
    status = 'PASS'
    version = $manifestVersion
    executable = $electronExe
    size = [int64]$item.Length
    product_version = $productVersion
    file_version = $fileVersion
    launch_mode = 'dependency_source'
    direct_process_probe = 'PASS'
  }
}

function Get-WaddlePepperFlashPath {
  param([Parameter(Mandatory)][string]$RepoRoot)
  Assert-WaddleWindowsOnly
  return Join-Path $RepoRoot 'assets\flash\pepflashplayer64_32_0_0_303.dll'
}

function Test-WaddlePepperFlash {
  param([Parameter(Mandatory)][string]$RepoRoot)

  Assert-WaddleWindowsOnly
  $path = if ($env:WADDLE_PPAPI_FLASH_PATH -and (Test-Path -LiteralPath $env:WADDLE_PPAPI_FLASH_PATH -PathType Leaf)) { [string]$env:WADDLE_PPAPI_FLASH_PATH } else { Get-WaddlePepperFlashPath -RepoRoot $RepoRoot }
  $path = [IO.Path]::GetFullPath($path)
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "WADDLE_PPAPI_FLASH=FAIL missing=$path"
  }
  $item = Get-Item -LiteralPath $path
  if ($item.Length -lt 1048576) {
    throw "WADDLE_PPAPI_FLASH=FAIL suspicious_size=$($item.Length) path=$path"
  }

  $version = if ($env:WADDLE_PPAPI_FLASH_VERSION) { [string]$env:WADDLE_PPAPI_FLASH_VERSION } else { '32.0.0.303' }
  if ($version -ne '32.0.0.303') { throw "WADDLE_PPAPI_FLASH=FAIL version_expected=32.0.0.303 actual=$version" }
  Write-Host "WADDLE_PPAPI_FLASH=PASS path=$path version=$version size=$($item.Length)"
  [pscustomobject]@{ status='PASS'; path=$path; version=$version; size=$item.Length }
}

function Test-WaddleRuntimeSnapshot {
  param(
    [Parameter(Mandatory)][string]$SnapshotRoot,
    [Parameter(Mandatory)][string]$SourceSha,
    [Parameter(Mandatory)][string]$DependencyFingerprint,
    [Parameter(Mandatory)][string]$ElectronVersion
  )

  $manifestPath = Join-Path $SnapshotRoot 'runtime-snapshot.json'
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return [pscustomobject]@{ ready=$false; reason='manifest_missing' } }
  try { $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json } catch { return [pscustomobject]@{ ready=$false; reason='manifest_invalid' } }
  if ([string]$manifest.source_sha -ne $SourceSha) { return [pscustomobject]@{ ready=$false; reason='source_sha_mismatch' } }
  if ([string]$manifest.dependency_fingerprint -ne $DependencyFingerprint) { return [pscustomobject]@{ ready=$false; reason='fingerprint_mismatch' } }
  if ([string]$manifest.electron_version -ne $ElectronVersion) { return [pscustomobject]@{ ready=$false; reason='electron_version_mismatch' } }

  $electron = Join-Path $SnapshotRoot 'electron\electron.exe'
  $icu = Join-Path $SnapshotRoot 'electron\icudtl.dat'
  $flash = Join-Path $SnapshotRoot ('flash\' + [string]$manifest.flash_file)
  foreach ($required in @($electron,$icu,$flash)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { return [pscustomobject]@{ ready=$false; reason="file_missing:$required" } }
  }

  if ((Get-FileHash -LiteralPath $electron -Algorithm SHA256).Hash -ne [string]$manifest.electron_sha256) { return [pscustomobject]@{ ready=$false; reason='electron_hash_mismatch' } }
  if ((Get-FileHash -LiteralPath $icu -Algorithm SHA256).Hash -ne [string]$manifest.icudtl_sha256) { return [pscustomobject]@{ ready=$false; reason='icudtl_hash_mismatch' } }
  if ((Get-FileHash -LiteralPath $flash -Algorithm SHA256).Hash -ne [string]$manifest.flash_sha256) { return [pscustomobject]@{ ready=$false; reason='flash_hash_mismatch' } }
  return [pscustomobject]@{ ready=$true; reason='valid'; manifest=$manifest; electron=$electron; flash=$flash; root=$SnapshotRoot }
}

function Remove-WaddleStaleRuntimeSnapshots {
  param(
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][string]$KeepRoot,
    [int]$Retain = 3
  )

  $interactive = Join-Path $WorkRoot 'runtime\interactive'
  if (-not (Test-Path -LiteralPath $interactive -PathType Container)) { return }
  $activeExecutables = New-Object System.Collections.Generic.List[string]
  foreach ($proc in @(Get-CimInstance Win32_Process -Filter "Name='electron.exe'" -ErrorAction SilentlyContinue)) {
    try {
      if ($proc.ExecutablePath) { $activeExecutables.Add([IO.Path]::GetFullPath([string]$proc.ExecutablePath)) }
    } catch {}
  }

  $dirs = @(Get-ChildItem -LiteralPath $interactive -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)
  $kept = 0
  foreach ($dir in $dirs) {
    $root = [IO.Path]::GetFullPath($dir.FullName)
    $electron = Join-Path $root 'electron\electron.exe'
    $active = @($activeExecutables | Where-Object { $_ -ieq $electron }).Count -gt 0
    if ($root.TrimEnd('\') -ieq ([IO.Path]::GetFullPath($KeepRoot)).TrimEnd('\') -or $active -or $kept -lt $Retain) {
      $kept++
      continue
    }
    try {
      Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
      Write-Host "WADDLE_RUNTIME_CLEANUP=PASS removed=$root"
    } catch {
      Write-Host "WADDLE_RUNTIME_CLEANUP=INFO preserved=$root reason=$($_.Exception.Message)"
    }
  }
}

function New-WaddleRuntimeSnapshot {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][string]$ElectronExecutable,
    [Parameter(Mandatory)][string]$ElectronVersion,
    [Parameter(Mandatory)][string]$PepperFlashPath,
    [Parameter(Mandatory)][string]$PepperFlashVersion,
    [Parameter(Mandatory)][string]$SourceSha,
    [Parameter(Mandatory)][string]$DependencyFingerprint
  )

  Assert-WaddleWindowsOnly
  if ($ElectronVersion -ne '10.4.7') { throw "WADDLE_RUNTIME_SNAPSHOT=FAIL electron_expected=10.4.7 actual=$ElectronVersion" }
  if ($PepperFlashVersion -ne '32.0.0.303') { throw "WADDLE_RUNTIME_SNAPSHOT=FAIL flash_expected=32.0.0.303 actual=$PepperFlashVersion" }
  foreach ($required in @($ElectronExecutable,$PepperFlashPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "WADDLE_RUNTIME_SNAPSHOT=FAIL source_missing=$required" }
  }

  $sourceDist = Split-Path -Parent ([IO.Path]::GetFullPath($ElectronExecutable))
  $sourceIcu = Join-Path $sourceDist 'icudtl.dat'
  if (-not (Test-Path -LiteralPath $sourceIcu -PathType Leaf)) { throw "WADDLE_RUNTIME_SNAPSHOT=FAIL icudtl_missing=$sourceIcu" }

  $shaToken = if ($SourceSha.Length -gt 12) { $SourceSha.Substring(0,12) } else { $SourceSha }
  $fingerToken = if ($DependencyFingerprint.Length -gt 12) { $DependencyFingerprint.Substring(0,12) } else { $DependencyFingerprint }
  $interactive = Join-Path $WorkRoot 'runtime\interactive'
  New-Item -ItemType Directory -Force -Path $interactive | Out-Null
  $target = Join-Path $interactive ("$shaToken-$fingerToken-e$ElectronVersion")
  $existing = Test-WaddleRuntimeSnapshot -SnapshotRoot $target -SourceSha $SourceSha -DependencyFingerprint $DependencyFingerprint -ElectronVersion $ElectronVersion
  if ($existing.ready) {
    $latestState = Join-Path $WorkRoot 'state\runtime-snapshot.json'
    $existing.manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $latestState -Encoding UTF8
    Remove-WaddleStaleRuntimeSnapshots -WorkRoot $WorkRoot -KeepRoot $target
    Write-Host "WADDLE_RUNTIME_SNAPSHOT=PASS mode=reused root=$target electron=$($existing.electron) flash=$($existing.flash)"
    return [pscustomobject]@{ status='PASS'; mode='reused'; root=$target; electron_executable=$existing.electron; ppapi_flash_path=$existing.flash; ppapi_flash_version=$PepperFlashVersion; manifest=$latestState }
  }

  if (Test-Path -LiteralPath $target) {
    $target = Join-Path $interactive ("$shaToken-$fingerToken-e$ElectronVersion-repair-" + (Get-Date -Format 'yyyyMMddHHmmss'))
  }
  $staging = Join-Path (Join-Path $WorkRoot 'runtime') ('.staging-' + [Guid]::NewGuid().ToString('N'))
  $stagingElectron = Join-Path $staging 'electron'
  $stagingFlash = Join-Path $staging 'flash'
  New-Item -ItemType Directory -Force -Path $stagingElectron,$stagingFlash | Out-Null

  try {
    $robocopy = Get-Command robocopy.exe -ErrorAction Stop
    & $robocopy.Source $sourceDist $stagingElectron /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    $copyExit = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($copyExit -ge 8) { throw "WADDLE_RUNTIME_SNAPSHOT=FAIL electron_copy_exit=$copyExit source=$sourceDist" }

    $flashFile = [IO.Path]::GetFileName($PepperFlashPath)
    $stagingFlashPath = Join-Path $stagingFlash $flashFile
    Copy-Item -LiteralPath $PepperFlashPath -Destination $stagingFlashPath -Force

    $stagingExe = Join-Path $stagingElectron 'electron.exe'
    $stagingIcu = Join-Path $stagingElectron 'icudtl.dat'
    foreach ($required in @($stagingExe,$stagingIcu,$stagingFlashPath)) {
      if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "WADDLE_RUNTIME_SNAPSHOT=FAIL staged_missing=$required" }
    }

    $electronHash = (Get-FileHash -LiteralPath $ElectronExecutable -Algorithm SHA256).Hash
    $icuHash = (Get-FileHash -LiteralPath $sourceIcu -Algorithm SHA256).Hash
    $flashHash = (Get-FileHash -LiteralPath $PepperFlashPath -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath $stagingExe -Algorithm SHA256).Hash -ne $electronHash) { throw 'WADDLE_RUNTIME_SNAPSHOT=FAIL electron_copy_hash' }
    if ((Get-FileHash -LiteralPath $stagingIcu -Algorithm SHA256).Hash -ne $icuHash) { throw 'WADDLE_RUNTIME_SNAPSHOT=FAIL icudtl_copy_hash' }
    if ((Get-FileHash -LiteralPath $stagingFlashPath -Algorithm SHA256).Hash -ne $flashHash) { throw 'WADDLE_RUNTIME_SNAPSHOT=FAIL flash_copy_hash' }

    $finalElectron = Join-Path $target 'electron\electron.exe'
    $finalFlash = Join-Path $target ('flash\' + $flashFile)
    $manifestData = [ordered]@{
      schema='waddle-runtime-snapshot/v1'
      status='PASS'
      platform='windows-x64'
      source_sha=$SourceSha
      dependency_fingerprint=$DependencyFingerprint
      electron_version=$ElectronVersion
      electron_executable=$finalElectron
      electron_sha256=$electronHash
      icudtl_sha256=$icuHash
      flash_file=$flashFile
      ppapi_flash_path=$finalFlash
      ppapi_flash_version=$PepperFlashVersion
      flash_sha256=$flashHash
      created_utc=[DateTime]::UtcNow.ToString('o')
    }
    $manifestData | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $staging 'runtime-snapshot.json') -Encoding UTF8
    Move-Item -LiteralPath $staging -Destination $target -ErrorAction Stop

    $validation = Test-WaddleRuntimeSnapshot -SnapshotRoot $target -SourceSha $SourceSha -DependencyFingerprint $DependencyFingerprint -ElectronVersion $ElectronVersion
    if (-not $validation.ready) { throw "WADDLE_RUNTIME_SNAPSHOT=FAIL post_move=$($validation.reason)" }
    $latestState = Join-Path $WorkRoot 'state\runtime-snapshot.json'
    $validation.manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $latestState -Encoding UTF8
    Remove-WaddleStaleRuntimeSnapshots -WorkRoot $WorkRoot -KeepRoot $target
    Write-Host "WADDLE_RUNTIME_SNAPSHOT=PASS mode=created root=$target electron=$($validation.electron) flash=$($validation.flash) dependency_tree_isolated=true"
    return [pscustomobject]@{ status='PASS'; mode='created'; root=$target; electron_executable=$validation.electron; ppapi_flash_path=$validation.flash; ppapi_flash_version=$PepperFlashVersion; manifest=$latestState }
  } finally {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
  }
}

function Set-WaddleEnvValue {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Value
  )

  $lines = if (Test-Path -LiteralPath $Path -PathType Leaf) { @(Get-Content -LiteralPath $Path) } else { @() }
  $escaped = [regex]::Escape($Name)
  $updated = New-Object System.Collections.Generic.List[string]
  $found = $false
  foreach ($line in $lines) {
    if ($line -match "^\s*$escaped=") {
      $updated.Add("$Name=$Value")
      $found = $true
    } else {
      $updated.Add([string]$line)
    }
  }
  if (-not $found) { $updated.Add("$Name=$Value") }
  Set-Content -LiteralPath $Path -Value $updated -Encoding UTF8
}

function Update-WaddleLocalEnv {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$AndroidBuildRoot,
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][string]$FFDecPath
  )

  Assert-WaddleWindowsOnly
  $envPath = Join-Path $RepoRoot '.env'
  $template = Join-Path $RepoRoot 'template.env'
  if (-not (Test-Path -LiteralPath $envPath -PathType Leaf)) {
    if (-not (Test-Path -LiteralPath $template -PathType Leaf)) { throw "WADDLE_ENV=FAIL template_missing=$template" }
    Copy-Item -LiteralPath $template -Destination $envPath
  }

  $modules = Get-WaddleNodeModulesPath -WorkRoot $WorkRoot
  $flash = Get-WaddlePepperFlashPath -RepoRoot $RepoRoot
  Set-WaddleEnvValue -Path $envPath -Name 'ANDROIDBUILD_ROOT' -Value ([IO.Path]::GetFullPath($AndroidBuildRoot))
  Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_REPO_ROOT' -Value ([IO.Path]::GetFullPath($RepoRoot))
  Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_WORK_ROOT' -Value ([IO.Path]::GetFullPath($WorkRoot))
  Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_NODE_MODULES' -Value $modules
  Set-WaddleEnvValue -Path $envPath -Name 'NODE_PATH' -Value $modules
  Set-WaddleEnvValue -Path $envPath -Name 'FFDEC_PATH' -Value ([IO.Path]::GetFullPath($FFDecPath))
  Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_PPAPI_FLASH_PATH' -Value ([IO.Path]::GetFullPath($flash))
  Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_PPAPI_FLASH_VERSION' -Value '32.0.0.303'
  Set-WaddleEnvValue -Path $envPath -Name 'YARN_CACHE_FOLDER' -Value ([IO.Path]::GetFullPath((Join-Path $WorkRoot 'cache\yarn')))
  Set-WaddleEnvValue -Path $envPath -Name 'WADDLE_RUNTIME_MODE' -Value 'immutable_snapshot'
  Write-Host "WADDLE_ENV=PASS mode=managed path=$envPath"
  return $envPath
}

function Import-WaddleLocalEnv {
  param([Parameter(Mandatory)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "WADDLE_ENV=FAIL missing=$Path" }
  foreach ($raw in Get-Content -LiteralPath $Path) {
    $line = ([string]$raw).Trim()
    if (-not $line -or $line.StartsWith('#')) { continue }
    $idx = $line.IndexOf('=')
    if ($idx -lt 1) { continue }
    $name = $line.Substring(0,$idx).Trim()
    $value = $line.Substring($idx+1)
    [Environment]::SetEnvironmentVariable($name,$value,'Process')
  }
  if ($env:WADDLE_WORK_ROOT) { Enable-WaddleLocalNodeTooling -WorkRoot $env:WADDLE_WORK_ROOT | Out-Null }
  Write-Host "WADDLE_ENV_IMPORT=PASS path=$Path"
}
