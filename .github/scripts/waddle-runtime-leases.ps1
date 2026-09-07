Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Cross-machine runtime leases for a repository that may be shared over SMB.
# Each Electron process owns one directory under .work\state\runtime-leases and
# refreshes its heartbeat periodically. Build/setup/dependency mutation is denied
# while any live lease exists. Read-only launches may coexist across machines.

function Get-WaddleRuntimeLeaseRoot {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return [IO.Path]::GetFullPath((Join-Path $RepoRoot '.work\state\runtime-leases'))
}

function Remove-WaddleRuntimeLeaseDirectory {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Reason)
  try {
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    Write-Host "WADDLE_RUNTIME_LEASE_CLEANUP=PASS path=$Path reason=$Reason"
    return $true
  } catch {
    Write-Host "WADDLE_RUNTIME_LEASE_CLEANUP=WARN path=$Path reason=$Reason error=$($_.Exception.Message)"
    return $false
  }
}

function Get-WaddleActiveRuntimeLeases {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [int]$StaleSeconds = 45
  )

  $root = Get-WaddleRuntimeLeaseRoot -RepoRoot $RepoRoot
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $now = [DateTime]::UtcNow
  $localMachine = ([string]$env:COMPUTERNAME).Trim()
  $active = New-Object System.Collections.Generic.List[object]

  foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
    $ownerPath = Join-Path $dir.FullName 'owner.json'
    $heartbeatPath = Join-Path $dir.FullName 'heartbeat'
    $owner = $null
    try {
      if (Test-Path -LiteralPath $ownerPath -PathType Leaf) {
        $owner = Get-Content -LiteralPath $ownerPath -Raw | ConvertFrom-Json -ErrorAction Stop
      }
    } catch {}

    $machine = if ($owner -and $owner.PSObject.Properties['machine']) { [string]$owner.machine } else { '' }
    $processId = 0
    if ($owner -and $owner.PSObject.Properties['pid']) {
      try { $processId = [int]$owner.pid } catch { $processId = 0 }
    }

    # For a lease owned by this machine, the process table is authoritative and
    # lets a force-killed client be cleaned immediately without waiting 45 s.
    if (-not [string]::IsNullOrWhiteSpace($machine) -and $machine -ieq $localMachine -and $processId -gt 0) {
      $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
      if ($process) {
        $active.Add([pscustomobject]@{ path=$dir.FullName; machine=$machine; pid=$processId; age_seconds=0; owner=$owner })
        continue
      }
      Remove-WaddleRuntimeLeaseDirectory -Path $dir.FullName -Reason 'local_process_missing' | Out-Null
      continue
    }

    $stamp = $null
    try {
      if (Test-Path -LiteralPath $heartbeatPath -PathType Leaf) {
        $stamp = (Get-Item -LiteralPath $heartbeatPath -Force).LastWriteTimeUtc
      } elseif (Test-Path -LiteralPath $ownerPath -PathType Leaf) {
        $stamp = (Get-Item -LiteralPath $ownerPath -Force).LastWriteTimeUtc
      } else {
        $stamp = $dir.LastWriteTimeUtc
      }
    } catch {}

    $age = if ($stamp) { [Math]::Max(0,[int](($now - $stamp).TotalSeconds)) } else { [int]::MaxValue }
    if ($age -le $StaleSeconds) {
      $active.Add([pscustomobject]@{ path=$dir.FullName; machine=$machine; pid=$processId; age_seconds=$age; owner=$owner })
      continue
    }

    Remove-WaddleRuntimeLeaseDirectory -Path $dir.FullName -Reason "stale_heartbeat_${age}s" | Out-Null
  }

  return @($active)
}

function Assert-WaddleRuntimeMutationAllowed {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Reason
  )

  $active = @(Get-WaddleActiveRuntimeLeases -RepoRoot $RepoRoot)
  if ($active.Count -gt 0) {
    $owners = @($active | ForEach-Object {
      $machine = if ([string]::IsNullOrWhiteSpace([string]$_.machine)) { 'unknown' } else { [string]$_.machine }
      "$machine:$($_.pid):$($_.age_seconds)s"
    }) -join ','
    throw "WADDLE_RUNTIME_MUTATION=BLOCKED reason=$Reason active_leases=$($active.Count) owners=$owners lease_root=$(Get-WaddleRuntimeLeaseRoot -RepoRoot $RepoRoot)"
  }
  Write-Host "WADDLE_RUNTIME_MUTATION=PASS reason=$Reason active_leases=0 scope=cross_machine"
}

function Test-WaddleDependencyMutationRequired {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$WorkRoot
  )

  $target = Get-WaddleNodeModulesPath -WorkRoot $WorkRoot
  if (-not (Test-Path -LiteralPath $target -PathType Container)) { return $true }

  $tree = Test-WaddleDependencyTree -RepoRoot $RepoRoot -WorkRoot $WorkRoot
  if (-not $tree.ready) { return $true }

  $fingerprint = Get-WaddleDependencyFingerprint -RepoRoot $RepoRoot
  $statePath = Join-Path $WorkRoot 'state\dependencies.json'
  if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $false }
  try {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -ErrorAction Stop
    return -not ([string]$state.fingerprint -eq $fingerprint -and [string]$state.root -eq 'node_modules')
  } catch {
    return $true
  }
}
