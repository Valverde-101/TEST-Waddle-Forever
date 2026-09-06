Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:WaddleNodeVersion = '20.19.0'
$script:WaddleYarnVersion = '1.22.22'
$script:WaddleNodeArchive = 'node-v20.19.0-win-x64.zip'
$script:WaddleNodeArchiveSha256 = 'be72284c7bc62de07d5a9fd0ae196879842c085f11f7f2b60bf8864c0c9d6a4f'
$script:WaddleNodeArchiveUrl = 'https://nodejs.org/dist/v20.19.0/node-v20.19.0-win-x64.zip'

function Test-WaddleNodeExecutable {
  param(
    [Parameter(Mandatory)][string]$Path,
    [string]$ExpectedVersion = $script:WaddleNodeVersion
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  try {
    $actual = (& $Path --version 2>$null).Trim().TrimStart('v')
    return $actual -eq $ExpectedVersion
  } catch {
    return $false
  }
}

function Get-WaddleManagedNodeLayout {
  param([Parameter(Mandatory)][string]$AndroidBuildRoot)

  $toolBase = [IO.Path]::GetFullPath((Join-Path $AndroidBuildRoot 'Tools\Node'))
  $home = [IO.Path]::GetFullPath((Join-Path $toolBase ($script:WaddleNodeVersion + '\x64')))
  [pscustomobject]@{
    tool_base = $toolBase
    home = $home
    node = (Join-Path $home 'node.exe')
    npm = (Join-Path $home 'npm.cmd')
    yarn = (Join-Path $home 'yarn.cmd')
    downloads = (Join-Path $toolBase '.downloads')
    staging = (Join-Path $toolBase '.staging')
    manifest = (Join-Path $home 'androidbuild-waddle-node.json')
  }
}

function Get-WaddleNodeCandidate {
  param(
    [Parameter(Mandatory)][string]$AndroidBuildRoot,
    [Parameter(Mandatory)][string]$ManagedHome
  )

  $candidates = New-Object System.Collections.Generic.List[string]

  $current = Get-Command node.exe -ErrorAction SilentlyContinue
  if (-not $current) { $current = Get-Command node -ErrorAction SilentlyContinue }
  if ($current -and $current.Source) { $candidates.Add([string]$current.Source) }

  foreach ($pattern in @(
    (Join-Path $AndroidBuildRoot 'Runners\Windows\slot-*\_work\_tool\node\20.19.0\x64\node.exe'),
    (Join-Path $AndroidBuildRoot 'Runners\AutoRepos\slot-*\_work\_tool\node\20.19.0\x64\node.exe')
  )) {
    foreach ($item in @(Get-Item -Path $pattern -ErrorAction SilentlyContinue)) {
      if ($item -and -not $candidates.Contains($item.FullName)) { $candidates.Add($item.FullName) }
    }
  }

  foreach ($candidate in $candidates) {
    if (-not (Test-WaddleNodeExecutable -Path $candidate)) { continue }
    $candidateHome = [IO.Path]::GetFullPath((Split-Path -Parent $candidate))
    if ($candidateHome.TrimEnd('\') -ieq $ManagedHome.TrimEnd('\')) { continue }
    return $candidate
  }
  return $null
}

function Install-WaddleManagedNodeFromCandidate {
  param(
    [Parameter(Mandatory)][string]$CandidateNode,
    [Parameter(Mandatory)][pscustomobject]$Layout
  )

  $sourceHome = Split-Path -Parent $CandidateNode
  $stage = Join-Path $Layout.staging ("node-{0}-{1}-{2}" -f $script:WaddleNodeVersion,$PID,[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $stage | Out-Null
  try {
    Copy-Item -Path (Join-Path $sourceHome '*') -Destination $stage -Recurse -Force
    if (-not (Test-WaddleNodeExecutable -Path (Join-Path $stage 'node.exe'))) {
      throw "WADDLE_MANAGED_NODE=FAIL candidate_copy_invalid source=$CandidateNode"
    }
    if (Test-Path -LiteralPath $Layout.home) { Remove-Item -LiteralPath $Layout.home -Recurse -Force }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Layout.home) | Out-Null
    Move-Item -LiteralPath $stage -Destination $Layout.home
  } finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
  }
  return "runner-cache:$CandidateNode"
}

function Install-WaddleManagedNodeFromOfficialArchive {
  param([Parameter(Mandatory)][pscustomobject]$Layout)

  New-Item -ItemType Directory -Force -Path $Layout.downloads,$Layout.staging | Out-Null
  $archive = Join-Path $Layout.downloads $script:WaddleNodeArchive
  $downloadRequired = $true
  if (Test-Path -LiteralPath $archive -PathType Leaf) {
    $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -eq $script:WaddleNodeArchiveSha256) { $downloadRequired = $false }
    else { Remove-Item -LiteralPath $archive -Force }
  }

  if ($downloadRequired) {
    Write-Host "WADDLE_MANAGED_NODE_DOWNLOAD=START url=$script:WaddleNodeArchiveUrl"
    $previousProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      Invoke-WebRequest -Uri $script:WaddleNodeArchiveUrl -OutFile $archive -UseBasicParsing
    } finally {
      [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
    }
  }

  $actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actualHash -ne $script:WaddleNodeArchiveSha256) {
    throw "WADDLE_MANAGED_NODE=FAIL archive_sha256 expected=$script:WaddleNodeArchiveSha256 actual=$actualHash path=$archive"
  }
  Write-Host "WADDLE_MANAGED_NODE_ARCHIVE=PASS sha256=$actualHash path=$archive"

  $stageRoot = Join-Path $Layout.staging ("extract-{0}-{1}-{2}" -f $script:WaddleNodeVersion,$PID,[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
  try {
    Expand-Archive -LiteralPath $archive -DestinationPath $stageRoot -Force
    $source = Join-Path $stageRoot 'node-v20.19.0-win-x64'
    $node = Join-Path $source 'node.exe'
    if (-not (Test-WaddleNodeExecutable -Path $node)) {
      throw "WADDLE_MANAGED_NODE=FAIL archive_extract_invalid path=$node"
    }
    if (Test-Path -LiteralPath $Layout.home) { Remove-Item -LiteralPath $Layout.home -Recurse -Force }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Layout.home) | Out-Null
    Move-Item -LiteralPath $source -Destination $Layout.home
  } finally {
    if (Test-Path -LiteralPath $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue }
  }
  return "official:$script:WaddleNodeArchiveUrl"
}

function Ensure-WaddleManagedYarn {
  param([Parameter(Mandatory)][pscustomobject]$Layout)

  if (-not (Test-WaddleNodeExecutable -Path $Layout.node)) {
    throw "WADDLE_MANAGED_YARN=FAIL node_invalid=$($Layout.node)"
  }

  $valid = $false
  if (Test-Path -LiteralPath $Layout.yarn -PathType Leaf) {
    try {
      $actual = (& $Layout.yarn --version 2>$null).Trim()
      $valid = $actual -eq $script:WaddleYarnVersion
    } catch {}
  }
  if ($valid) {
    Write-Host "WADDLE_MANAGED_YARN=PASS version=$script:WaddleYarnVersion mode=existing path=$($Layout.yarn)"
    return
  }

  if (-not (Test-Path -LiteralPath $Layout.npm -PathType Leaf)) {
    throw "WADDLE_MANAGED_YARN=FAIL npm_missing=$($Layout.npm)"
  }

  Write-Host "WADDLE_MANAGED_YARN_INSTALL=START version=$script:WaddleYarnVersion prefix=$($Layout.home)"
  & $Layout.npm install --global ("yarn@" + $script:WaddleYarnVersion) --prefix $Layout.home --no-audit --no-fund
  $exit = $LASTEXITCODE
  if ($exit -ne 0) { throw "WADDLE_MANAGED_YARN=FAIL npm_exit=$exit" }
  if (-not (Test-Path -LiteralPath $Layout.yarn -PathType Leaf)) {
    throw "WADDLE_MANAGED_YARN=FAIL yarn_missing_after_install=$($Layout.yarn)"
  }
  $actual = (& $Layout.yarn --version).Trim()
  if ($actual -ne $script:WaddleYarnVersion) {
    throw "WADDLE_MANAGED_YARN=FAIL required=$script:WaddleYarnVersion actual=$actual path=$($Layout.yarn)"
  }
  Write-Host "WADDLE_MANAGED_YARN=PASS version=$actual mode=installed path=$($Layout.yarn)"
}

function Ensure-WaddleManagedNodeToolchain {
  param([Parameter(Mandatory)][string]$AndroidBuildRoot)

  if ($env:OS -ne 'Windows_NT') { throw 'WADDLE_MANAGED_NODE=FAIL windows_required' }
  if (-not [Environment]::Is64BitOperatingSystem) { throw 'WADDLE_MANAGED_NODE=FAIL x64_windows_required' }

  $layout = Get-WaddleManagedNodeLayout -AndroidBuildRoot $AndroidBuildRoot
  New-Item -ItemType Directory -Force -Path $layout.tool_base,$layout.staging | Out-Null

  $mutex = New-Object Threading.Mutex($false,'Global\AndroidBuild-Waddle-Node-20.19.0-x64')
  $acquired = $false
  try {
    $acquired = $mutex.WaitOne([TimeSpan]::FromMinutes(10))
    if (-not $acquired) { throw 'WADDLE_MANAGED_NODE=FAIL lock_timeout=600s' }

    $source = 'existing'
    if (-not (Test-WaddleNodeExecutable -Path $layout.node)) {
      $candidate = Get-WaddleNodeCandidate -AndroidBuildRoot $AndroidBuildRoot -ManagedHome $layout.home
      if ($candidate) {
        $source = Install-WaddleManagedNodeFromCandidate -CandidateNode $candidate -Layout $layout
      } else {
        $source = Install-WaddleManagedNodeFromOfficialArchive -Layout $layout
      }
    }

    if (-not (Test-WaddleNodeExecutable -Path $layout.node)) {
      throw "WADDLE_MANAGED_NODE=FAIL final_validation path=$($layout.node)"
    }
    Ensure-WaddleManagedYarn -Layout $layout

    $manifest = [ordered]@{
      schema = 'androidbuild-waddle-node/v1'
      node_version = $script:WaddleNodeVersion
      yarn_version = $script:WaddleYarnVersion
      architecture = 'x64'
      node_home = $layout.home
      node_exe = $layout.node
      yarn_cmd = $layout.yarn
      source = $source
      official_archive = $script:WaddleNodeArchiveUrl
      official_archive_sha256 = $script:WaddleNodeArchiveSha256
      verified_utc = [DateTime]::UtcNow.ToString('o')
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $layout.manifest -Encoding UTF8
  } finally {
    if ($acquired) { try { $mutex.ReleaseMutex() } catch {} }
    $mutex.Dispose()
  }

  [pscustomobject]@{
    status = 'PASS'
    node_version = $script:WaddleNodeVersion
    yarn_version = $script:WaddleYarnVersion
    home = $layout.home
    node = $layout.node
    npm = $layout.npm
    yarn = $layout.yarn
    manifest = $layout.manifest
  }
}

function Enable-WaddleManagedNodeToolchain {
  param([Parameter(Mandatory)][string]$AndroidBuildRoot)

  $managed = Ensure-WaddleManagedNodeToolchain -AndroidBuildRoot $AndroidBuildRoot
  $parts = @([string]$env:PATH -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ine $managed.home.TrimEnd('\') })
  $env:PATH = @($managed.home) + $parts -join ';'
  $env:WADDLE_NODE_HOME = $managed.home
  $env:WADDLE_NODE_EXE = $managed.node
  $env:WADDLE_NPM_CMD = $managed.npm
  $env:WADDLE_YARN_CMD = $managed.yarn

  $selectedNode = (Get-Command node.exe -ErrorAction Stop).Source
  $nodeVersion = (& $selectedNode --version).Trim().TrimStart('v')
  $selectedYarn = (Get-Command yarn.cmd -ErrorAction Stop).Source
  $yarnVersion = (& $selectedYarn --version).Trim()
  if ($nodeVersion -ne $script:WaddleNodeVersion) {
    throw "WADDLE_MANAGED_NODE=FAIL selected_version required=$script:WaddleNodeVersion actual=$nodeVersion path=$selectedNode"
  }
  if ($yarnVersion -ne $script:WaddleYarnVersion) {
    throw "WADDLE_MANAGED_YARN=FAIL selected_version required=$script:WaddleYarnVersion actual=$yarnVersion path=$selectedYarn"
  }
  if ([IO.Path]::GetFullPath($selectedNode) -ne [IO.Path]::GetFullPath($managed.node)) {
    throw "WADDLE_MANAGED_NODE=FAIL selection_not_managed selected=$selectedNode expected=$($managed.node)"
  }

  Write-Host "WADDLE_MANAGED_NODE=PASS version=$nodeVersion path=$selectedNode host_node_isolated=true"
  Write-Host "WADDLE_MANAGED_YARN=PASS version=$yarnVersion path=$selectedYarn host_yarn_isolated=true"
  return $managed
}
