Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Enable-WaddleLocalNodeTooling {
  param([Parameter(Mandatory)][string]$WorkRoot)

  $modules = [IO.Path]::GetFullPath((Join-Path $WorkRoot 'dependencies\node_modules'))
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
  Write-Host "WADDLE_JUNCTION_REMOVE=PASS path=$Path"
}

function Install-WaddleDependencies {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$WorkRoot
  )

  $target = Join-Path $WorkRoot 'dependencies\node_modules'
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

  $yarn = Get-Command yarn.cmd -ErrorAction SilentlyContinue
  if (-not $yarn) { $yarn = Get-Command yarn -ErrorAction Stop }

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
  if (-not ([string]$electron.version).StartsWith('10.')) {
    throw "WADDLE_DEPENDENCIES=FAIL electron_legacy_contract expected_major=10 actual=$($electron.version)"
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

  $modules = [IO.Path]::GetFullPath((Join-Path $WorkRoot 'dependencies\node_modules'))
  $manifestPath = Join-Path $modules 'electron\package.json'
  $electronExe = [IO.Path]::GetFullPath((Join-Path $modules 'electron\dist\electron.exe'))

  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "WADDLE_ELECTRON_RUNTIME=FAIL manifest_missing=$manifestPath"
  }
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  $manifestVersion = [string]$manifest.version
  if ([string]::IsNullOrWhiteSpace($manifestVersion)) {
    throw "WADDLE_ELECTRON_RUNTIME=FAIL manifest_version_empty=$manifestPath"
  }
  if ($manifestVersion -ne $ExpectedVersion) {
    throw "WADDLE_ELECTRON_RUNTIME=FAIL manifest_version_mismatch expected=$ExpectedVersion actual=$manifestVersion manifest=$manifestPath"
  }
  if (-not $manifestVersion.StartsWith('10.')) {
    throw "WADDLE_ELECTRON_RUNTIME=FAIL legacy_contract expected_major=10 actual=$manifestVersion"
  }
  if (-not (Test-Path -LiteralPath $electronExe -PathType Leaf)) {
    throw "WADDLE_ELECTRON_RUNTIME=FAIL executable_missing=$electronExe"
  }

  $item = Get-Item -LiteralPath $electronExe -Force
  if ($item.Length -lt 1048576) {
    throw "WADDLE_ELECTRON_RUNTIME=FAIL suspicious_size=$($item.Length) executable=$electronExe"
  }

  # Verify the executable is actually a PE image, without reading the entire
  # Electron binary into memory.
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

  # Do not use `electron.exe --version` as a health gate: Electron 10 is a GUI
  # subsystem executable and service-hosted PowerShell does not reliably receive
  # its stdout. Instead run the exact packaged executable directly in
  # ELECTRON_RUN_AS_NODE mode and require a clean process exit. This validates
  # Windows process creation from the mapped repository without cmd.exe or the
  # node_modules\.bin\electron.cmd shim.
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
  Write-Host "WADDLE_ELECTRON_RUNTIME=PASS version=$manifestVersion executable=$electronExe size=$($item.Length) pe=MZ direct_process_probe=PASS launch_mode=direct_exe product_version=$productVersion file_version=$fileVersion"
  [pscustomobject]@{
    status = 'PASS'
    version = $manifestVersion
    executable = $electronExe
    size = [int64]$item.Length
    product_version = $productVersion
    file_version = $fileVersion
    launch_mode = 'direct_exe'
    direct_process_probe = 'PASS'
  }
}

function Get-WaddlePepperFlashPath {
  param([Parameter(Mandatory)][string]$RepoRoot)

  if ($env:PROCESSOR_ARCHITECTURE -match '86' -and -not [Environment]::Is64BitProcess) {
    return Join-Path $RepoRoot 'assets\flash\pepflashplayer32_32_0_0_303.dll'
  }
  return Join-Path $RepoRoot 'assets\flash\pepflashplayer64_32_0_0_303.dll'
}

function Test-WaddlePepperFlash {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $path = if ($env:WADDLE_PPAPI_FLASH_PATH) { [string]$env:WADDLE_PPAPI_FLASH_PATH } else { Get-WaddlePepperFlashPath -RepoRoot $RepoRoot }
  $path = [IO.Path]::GetFullPath($path)
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "WADDLE_PPAPI_FLASH=FAIL missing=$path"
  }
  $item = Get-Item -LiteralPath $path
  if ($item.Length -lt 1048576) {
    throw "WADDLE_PPAPI_FLASH=FAIL suspicious_size=$($item.Length) path=$path"
  }

  $version = if ($env:WADDLE_PPAPI_FLASH_VERSION) { [string]$env:WADDLE_PPAPI_FLASH_VERSION } else { '32.0.0.303' }
  Write-Host "WADDLE_PPAPI_FLASH=PASS path=$path version=$version size=$($item.Length)"
  [pscustomobject]@{ status='PASS'; path=$path; version=$version; size=$item.Length }
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

  $envPath = Join-Path $RepoRoot '.env'
  $template = Join-Path $RepoRoot 'template.env'
  if (-not (Test-Path -LiteralPath $envPath -PathType Leaf)) {
    if (-not (Test-Path -LiteralPath $template -PathType Leaf)) { throw "WADDLE_ENV=FAIL template_missing=$template" }
    Copy-Item -LiteralPath $template -Destination $envPath
  }

  $modules = [IO.Path]::GetFullPath((Join-Path $WorkRoot 'dependencies\node_modules'))
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
