[CmdletBinding()]
param(
  [string]$RepoRoot,
  [string]$WorkRoot,
  [string]$FFDecPath,
  [ValidateRange(1,200)][int]$DeepBudget = 2,
  [ValidateRange(5,120)][int]$FFDecTimeoutSeconds = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) { $RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')) }
else { $RepoRoot = [IO.Path]::GetFullPath($RepoRoot) }
if (-not $WorkRoot) { $WorkRoot = Join-Path $RepoRoot '.work' }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
$analysisRoot = Join-Path $WorkRoot 'swf-analysis'
$cacheRoot = Join-Path $analysisRoot 'cache'
$dumpRoot = Join-Path $analysisRoot 'ffdec'
$hashIndexPath = Join-Path $analysisRoot 'hash-index.json'
New-Item -ItemType Directory -Force -Path $analysisRoot,$cacheRoot,$dumpRoot | Out-Null

function Get-RelativePath {
  param([Parameter(Mandatory)][string]$Base,[Parameter(Mandatory)][string]$Path)
  $baseUri = New-Object Uri(($Base.TrimEnd('\') + '\'))
  $pathUri = New-Object Uri($Path)
  [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/','\')
}

function Get-PrintableText {
  param([Parameter(Mandatory)][string]$Path)
  $bytes = [IO.File]::ReadAllBytes($Path)
  $text = [Text.Encoding]::GetEncoding(28591).GetString($bytes)
  [regex]::Replace($text, '[^\x20-\x7E\r\n\t]', ' ')
}

function Get-ReferenceData {
  param([Parameter(Mandatory)][string]$Text)
  $urls = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
  $swfs = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
  $protocols = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
  foreach ($m in [regex]::Matches($Text, '(?i)\b(?:https?|wss?|rtmp|socket)://[^\s"''<>]+')) {
    $value = $m.Value.TrimEnd(')',']','}',',',';')
    [void]$urls.Add($value)
    [void]$protocols.Add($value.Split(':')[0].ToLowerInvariant())
  }
  foreach ($m in [regex]::Matches($Text, '(?i)(?:[A-Za-z0-9_@%+=:,./-]+)?[A-Za-z0-9_@%+=,-]+\.swf(?:\?[^\s"''<>]*)?')) {
    $value = $m.Value.Replace('/','\').TrimStart('.','\')
    if ($value.Length -le 512) { [void]$swfs.Add($value) }
  }
  foreach ($token in @('XMLSocket','Socket','SmartFox','RTMP','WebSocket')) {
    if ($Text -match ('(?i)\b' + [regex]::Escape($token) + '\b')) { [void]$protocols.Add($token.ToLowerInvariant()) }
  }
  [pscustomobject]@{ urls=@($urls | Sort-Object); swf_refs=@($swfs | Sort-Object); protocols=@($protocols | Sort-Object) }
}

function Test-CurrentCacheItem {
  param([object]$Item)
  if ($null -eq $Item) { return $false }
  $schemaProperty = $Item.PSObject.Properties['schema']
  $statusProperty = $Item.PSObject.Properties['status']
  if ($null -eq $schemaProperty -or $null -eq $statusProperty) { return $false }
  if ([string]$schemaProperty.Value -ne 'waddle-swf-analysis-item/v2') { return $false }
  return [string]$statusProperty.Value -eq 'ANALYZED'
}

function Get-OptionalPropertyValue {
  param(
    [object]$Object,
    [Parameter(Mandatory)][string]$Name,
    [object]$Default = $null
  )
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $Default }
  return $property.Value
}

function Invoke-FFDecDump {
  param(
    [Parameter(Mandatory)][string]$FFDec,
    [Parameter(Mandatory)][ValidateSet('AS2','AS3')][string]$Kind,
    [Parameter(Mandatory)][string]$Swf,
    [Parameter(Mandatory)][string]$OutFile,
    [Parameter(Mandatory)][string]$ErrFile,
    [Parameter(Mandatory)][int]$TimeoutSeconds
  )
  Remove-Item -LiteralPath $OutFile,$ErrFile -Force -ErrorAction SilentlyContinue
  $arg = if ($Kind -eq 'AS2') { '-dumpAS2' } else { '-dumpAS3' }
  $quotedSwf = '"' + $Swf.Replace('"','\"') + '"'
  $started = [DateTime]::UtcNow
  $proc = Start-Process -FilePath $FFDec -ArgumentList @('-cli',$arg,$quotedSwf) -RedirectStandardOutput $OutFile -RedirectStandardError $ErrFile -PassThru -WindowStyle Hidden
  if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    try { $proc.Kill() } catch {}
    try { [void]$proc.WaitForExit(3000) } catch {}
    return [pscustomobject]@{ status='TIMEOUT'; exit=-1; output=$OutFile; error=$ErrFile; duration_ms=[int]([DateTime]::UtcNow-$started).TotalMilliseconds }
  }
  $proc.Refresh()
  return [pscustomobject]@{ status=$(if ($proc.ExitCode -eq 0) {'PASS'} else {'FAIL'}); exit=[int]$proc.ExitCode; output=$OutFile; error=$ErrFile; duration_ms=[int]([DateTime]::UtcNow-$started).TotalMilliseconds }
}

if (-not $FFDecPath) {
  if ($env:FFDEC_PATH) { $FFDecPath = $env:FFDEC_PATH }
  elseif ($env:WADDLE_FFDEC) { $FFDecPath = $env:WADDLE_FFDEC }
}
if (-not $FFDecPath -or -not (Test-Path -LiteralPath $FFDecPath -PathType Leaf)) { throw "WADDLE_SWF_ANALYSIS=FAIL ffdec_missing path=$FFDecPath" }
$FFDecPath = [IO.Path]::GetFullPath($FFDecPath)

$previousHashIndex = @{}
if (Test-Path -LiteralPath $hashIndexPath -PathType Leaf) {
  try {
    foreach ($entry in @((Get-Content -LiteralPath $hashIndexPath -Raw | ConvertFrom-Json))) {
      if ($null -eq $entry) { continue }
      $pathProperty = $entry.PSObject.Properties['path']
      $hashProperty = $entry.PSObject.Properties['sha256']
      $sizeProperty = $entry.PSObject.Properties['size']
      $mtimeProperty = $entry.PSObject.Properties['modified_utc']
      if ($null -eq $pathProperty -or $null -eq $hashProperty -or $null -eq $sizeProperty -or $null -eq $mtimeProperty) { continue }
      $hashText = [string]$hashProperty.Value
      if ($hashText -notmatch '^[0-9a-fA-F]{64}$') { continue }
      $previousHashIndex[[string]$pathProperty.Value.ToLowerInvariant()] = $entry
    }
  } catch {
    $previousHashIndex = @{}
  }
}

$scanRoots = @((Join-Path $RepoRoot 'media'),(Join-Path $RepoRoot 'assets')) | Where-Object { Test-Path -LiteralPath $_ -PathType Container }
$swfFiles = @($scanRoots | ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter '*.swf' -File -Recurse -ErrorAction SilentlyContinue } | Sort-Object FullName -Unique)
$inventory = New-Object System.Collections.Generic.List[object]
$newHashIndex = New-Object System.Collections.Generic.List[object]
$byLeaf = @{}
$byRelative = @{}
$byHash = @{}
$hashCacheReused = 0
$hashRecomputed = 0

foreach ($file in $swfFiles) {
  $relative = Get-RelativePath -Base $RepoRoot -Path $file.FullName
  $relativeKey = $relative.ToLowerInvariant()
  $modifiedUtc = $file.LastWriteTimeUtc.ToString('o')
  $hash = $null

  if ($previousHashIndex.ContainsKey($relativeKey)) {
    $prior = $previousHashIndex[$relativeKey]
    if ([int64]$prior.size -eq [int64]$file.Length -and [string]$prior.modified_utc -eq $modifiedUtc) {
      $hash = ([string]$prior.sha256).ToLowerInvariant()
      $hashCacheReused++
    }
  }

  if (-not $hash) {
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $hashRecomputed++
  }

  $item = [pscustomobject]@{ path=$relative; sha256=$hash; size=[int64]$file.Length; modified_utc=$modifiedUtc }
  $inventory.Add($item)
  $newHashIndex.Add($item)

  $leaf = $file.Name.ToLowerInvariant()
  if (-not $byLeaf.ContainsKey($leaf)) { $byLeaf[$leaf] = New-Object System.Collections.Generic.List[string] }
  $byLeaf[$leaf].Add($relative)
  $byRelative[$relativeKey] = $relative

  if (-not $byHash.ContainsKey($hash)) { $byHash[$hash] = New-Object System.Collections.Generic.List[object] }
  $byHash[$hash].Add($item)
}
$newHashIndex | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $hashIndexPath -Encoding UTF8

$analysisByHash = @{}
$staleCacheCount = 0
$uniqueGroups = New-Object System.Collections.Generic.List[object]
foreach ($hash in @($byHash.Keys | Sort-Object)) {
  $paths = @($byHash[$hash] | Sort-Object path)
  $representative = $paths[0]
  $hasBoots = @($paths | Where-Object { [IO.Path]::GetFileName($_.path) -ieq 'boots.swf' }).Count -gt 0
  if ($hasBoots) {
    $representative = @($paths | Where-Object { [IO.Path]::GetFileName($_.path) -ieq 'boots.swf' } | Select-Object -First 1)[0]
  }

  $cachePath = Join-Path $cacheRoot ($hash + '.json')
  $cached = $null
  if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
    try {
      $candidate = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
      if (Test-CurrentCacheItem -Item $candidate) {
        $cached = $candidate
        $analysisByHash[$hash] = $candidate
      } else {
        $staleCacheCount++
      }
    } catch {
      $staleCacheCount++
    }
  }

  $uniqueGroups.Add([pscustomobject]@{
    sha256=$hash
    representative=$representative
    duplicate_count=$paths.Count
    has_boots=$hasBoots
    cached=($null -ne $cached)
  })
}

$runtimeSwfByLeaf = @{}
$runtimePrioritySource = $null
$runtimeMalformedTraceCount = 0
$runtimeLogRoot = Join-Path $WorkRoot 'logs\runtime'
if (Test-Path -LiteralPath $runtimeLogRoot -PathType Container) {
  $runtimeLog = Get-ChildItem -LiteralPath $runtimeLogRoot -File -Filter 'client-*.stderr.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if ($runtimeLog) {
    $runtimePrioritySource = $runtimeLog.FullName
    foreach ($line in Get-Content -LiteralPath $runtimeLog.FullName -ErrorAction SilentlyContinue) {
      $text = ([string]$line).Trim()
      if (-not $text.StartsWith('{')) { continue }
      try { $evt = $text | ConvertFrom-Json } catch { continue }

      $eventName = [string](Get-OptionalPropertyValue -Object $evt -Name 'event' -Default '')
      if ($eventName -ne 'live-trace') { continue }
      $trace = Get-OptionalPropertyValue -Object $evt -Name 'trace'
      if ($null -eq $trace) { $runtimeMalformedTraceCount++; continue }
      $category = [string](Get-OptionalPropertyValue -Object $trace -Name 'category' -Default '')
      if ($category -ne 'SWF') { continue }

      $action = [string](Get-OptionalPropertyValue -Object $trace -Name 'action' -Default '')
      $url = [string](Get-OptionalPropertyValue -Object $trace -Name 'url' -Default '')
      $phase = ([string](Get-OptionalPropertyValue -Object $trace -Name 'phase' -Default '')).ToLowerInvariant()
      $statusValue = Get-OptionalPropertyValue -Object $trace -Name 'statusCode' -Default 0
      $code = 0
      if ($null -ne $statusValue -and [string]$statusValue -match '^\d+$') { $code = [int]$statusValue }

      $identity = if ($action) { $action } else { $url }
      $leaf = [IO.Path]::GetFileName(([string]$identity).Split('?')[0]).ToLowerInvariant()
      if (-not $leaf -or $leaf -notmatch '\.swf$') { $runtimeMalformedTraceCount++; continue }

      $rank = if ($phase -eq 'error' -or $code -ge 400) { 0 } elseif ($phase -eq 'request') { 1 } else { 2 }
      if (-not $runtimeSwfByLeaf.ContainsKey($leaf) -or $rank -lt [int]$runtimeSwfByLeaf[$leaf].rank) {
        $runtimeSwfByLeaf[$leaf] = [pscustomobject]@{
          leaf=$leaf
          rank=$rank
          phase=$phase
          status_code=$code
          action=$action
          url=$url
        }
      }
    }
  }
}

$runtimePrioritizedHashes = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
foreach ($group in $uniqueGroups) {
  $runtimeRank = 9
  foreach ($pathItem in @($byHash[$group.sha256])) {
    $leaf = [IO.Path]::GetFileName([string]$pathItem.path).ToLowerInvariant()
    if ($runtimeSwfByLeaf.ContainsKey($leaf)) {
      $candidateRank = [int]$runtimeSwfByLeaf[$leaf].rank
      if ($candidateRank -lt $runtimeRank) { $runtimeRank = $candidateRank }
    }
  }
  if ($runtimeRank -lt 9) { [void]$runtimePrioritizedHashes.Add([string]$group.sha256) }
  Add-Member -InputObject $group -NotePropertyName runtime_rank -NotePropertyValue $runtimeRank -Force
}

$deepCandidates = @($uniqueGroups |
  Where-Object { -not $_.cached } |
  Sort-Object @{Expression={ [int]$_.runtime_rank }}, @{Expression={ if ($_.has_boots) {0} else {1} }}, @{Expression={ $_.representative.path }})
$selectedGroups = @($deepCandidates | Select-Object -First $DeepBudget)

foreach ($group in $selectedGroups) {
  $item = $group.representative
  $full = Join-Path $RepoRoot $item.path
  $parts = New-Object System.Collections.Generic.List[string]
  $parts.Add((Get-PrintableText -Path $full))
  $ffdecRuns = @()

  foreach ($kind in @('AS2','AS3')) {
    $prefix = Join-Path $dumpRoot ($item.sha256 + '.' + $kind.ToLowerInvariant())
    $run = Invoke-FFDecDump -FFDec $FFDecPath -Kind $kind -Swf $full -OutFile ($prefix + '.txt') -ErrFile ($prefix + '.stderr.txt') -TimeoutSeconds $FFDecTimeoutSeconds
    if ($null -eq $run -or $null -eq $run.PSObject.Properties['status'] -or $null -eq $run.PSObject.Properties['exit']) {
      throw "WADDLE_SWF_ANALYSIS=FAIL ffdec_result_contract kind=$kind swf=$($item.path)"
    }
    $ffdecRuns += [pscustomobject]@{
      kind=$kind
      status=[string]$run.status
      exit=[int]$run.exit
      duration_ms=$(if ($null -ne $run.PSObject.Properties['duration_ms']) { [int]$run.duration_ms } else { $null })
    }
    if ($null -ne $run.PSObject.Properties['output'] -and (Test-Path -LiteralPath ([string]$run.output) -PathType Leaf)) {
      try { $parts.Add((Get-Content -LiteralPath ([string]$run.output) -Raw -ErrorAction Stop)) } catch {}
    }
  }

  $refs = Get-ReferenceData -Text ($parts -join "`n")
  $analysis = [pscustomobject]@{
    schema='waddle-swf-analysis-item/v2'
    status='ANALYZED'
    path=$item.path
    sha256=$item.sha256
    size=$item.size
    duplicate_count=[int]$group.duplicate_count
    deep=$true
    ffdec=@($ffdecRuns)
    urls=@($refs.urls)
    protocols=@($refs.protocols)
    swf_refs=@($refs.swf_refs)
    analyzed_utc=[DateTime]::UtcNow.ToString('o')
  }
  $cachePath = Join-Path $cacheRoot ($item.sha256 + '.json')
  $analysis | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $cachePath -Encoding UTF8
  $analysisByHash[$item.sha256] = $analysis
}

$results = New-Object System.Collections.Generic.List[object]
$allUrls = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
$allProtocols = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
$edges = New-Object System.Collections.Generic.List[object]
$missing = New-Object System.Collections.Generic.List[object]

foreach ($item in $inventory) {
  $template = if ($analysisByHash.ContainsKey($item.sha256)) { $analysisByHash[$item.sha256] } else { $null }
  $analysis = if ($null -ne $template) {
    [pscustomobject]@{
      schema='waddle-swf-analysis-item/v2'
      status='ANALYZED'
      path=$item.path
      canonical_path=[string]$template.path
      sha256=$item.sha256
      size=$item.size
      duplicate_count=[int]$byHash[$item.sha256].Count
      deep=$true
      ffdec=@($template.ffdec)
      urls=@($template.urls)
      protocols=@($template.protocols)
      swf_refs=@($template.swf_refs)
      analyzed_utc=$template.analyzed_utc
    }
  } else {
    [pscustomobject]@{
      schema='waddle-swf-analysis-item/v2'
      status='PENDING_DEEP'
      path=$item.path
      canonical_path=$null
      sha256=$item.sha256
      size=$item.size
      duplicate_count=[int]$byHash[$item.sha256].Count
      deep=$false
      ffdec=@()
      urls=@()
      protocols=@()
      swf_refs=@()
      analyzed_utc=$null
    }
  }

  if ([string]$analysis.status -eq 'ANALYZED') {
    foreach ($url in @($analysis.urls)) { if ($url) { [void]$allUrls.Add([string]$url) } }
    foreach ($protocol in @($analysis.protocols)) { if ($protocol) { [void]$allProtocols.Add([string]$protocol) } }
    foreach ($ref in @($analysis.swf_refs)) {
      if (-not $ref) { continue }
      $rawRef = ([string]$ref).Split('?')[0].Replace('/','\').TrimStart('.','\')
      $leaf = [IO.Path]::GetFileName($rawRef).ToLowerInvariant()
      $targets = @()
      if ($byRelative.ContainsKey($rawRef.ToLowerInvariant())) { $targets = @($byRelative[$rawRef.ToLowerInvariant()]) }
      elseif ($byLeaf.ContainsKey($leaf)) { $targets = @($byLeaf[$leaf]) }
      if ($targets.Count -gt 0) {
        foreach ($target in $targets) { $edges.Add([pscustomobject]@{ source=$item.path; reference=$ref; target=$target }) }
      } else {
        $missing.Add([pscustomobject]@{ source=$item.path; reference=$ref; leaf=$leaf; classification='unresolved_literal_swf_reference' })
      }
    }
  }
  $results.Add($analysis)
}

$probePath = Join-Path $WorkRoot 'state\flash-runtime-probe.json'
$runtimeTrace = [ordered]@{ schema='waddle-swf-runtime-trace/v1'; source=$probePath; available=$false; production_url=$null; observed_responses=@(); renderer=$null }
if (Test-Path -LiteralPath $probePath -PathType Leaf) {
  try {
    $probe = Get-Content -LiteralPath $probePath -Raw | ConvertFrom-Json
    $runtimeTrace.available=$true
    $runtimeTrace.production_url=$probe.production_url
    $runtimeTrace.observed_responses=@($probe.observed_responses)
    $runtimeTrace.renderer=$probe.renderer
  } catch {}
}

$analyzedUnique = $analysisByHash.Count
$analyzedPaths = @($results | Where-Object { [string]$_.status -eq 'ANALYZED' }).Count
$uniqueCount = $uniqueGroups.Count
$summary = [ordered]@{
  schema='waddle-swf-analysis/v4'
  status='PASS'
  repository_root=$RepoRoot
  ffdec=$FFDecPath
  source_mutation=$false
  swf_path_count=$inventory.Count
  unique_hash_count=$uniqueCount
  duplicate_path_count=($inventory.Count-$uniqueCount)
  hash_cache_reused=$hashCacheReused
  hash_recomputed=$hashRecomputed
  deep_budget_unique_hashes=$DeepBudget
  deep_selected_unique_hashes=$selectedGroups.Count
  runtime_priority_source=$runtimePrioritySource
  runtime_observed_swf_count=$runtimeSwfByLeaf.Count
  runtime_malformed_trace_count=$runtimeMalformedTraceCount
  runtime_prioritized_unique_hash_count=$runtimePrioritizedHashes.Count
  runtime_selected_unique_hash_count=@($selectedGroups | Where-Object { [int]$_.runtime_rank -lt 9 }).Count
  analyzed_unique_hash_count=$analyzedUnique
  pending_unique_hash_count=($uniqueCount-$analyzedUnique)
  analyzed_path_count=$analyzedPaths
  pending_path_count=($inventory.Count-$analyzedPaths)
  stale_cache_ignored=$staleCacheCount
  dependency_edges=$edges.Count
  unresolved_literal_refs=$missing.Count
  url_count=$allUrls.Count
  protocols=@($allProtocols | Sort-Object)
  runtime_trace_available=[bool]$runtimeTrace.available
  generated_utc=[DateTime]::UtcNow.ToString('o')
}

$inventory | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $analysisRoot 'manifest.json') -Encoding UTF8
$results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $analysisRoot 'items.json') -Encoding UTF8
$edges | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $analysisRoot 'dependency-graph.json') -Encoding UTF8
@($allUrls | Sort-Object) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $analysisRoot 'urls.json') -Encoding UTF8
$missing | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $analysisRoot 'missing-swfs.json') -Encoding UTF8
$runtimeTrace | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $analysisRoot 'runtime-trace.json') -Encoding UTF8
@($runtimeSwfByLeaf.Values | Sort-Object rank,leaf) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $analysisRoot 'runtime-priority.json') -Encoding UTF8
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $analysisRoot 'summary.json') -Encoding UTF8
Write-Host "WADDLE_SWF_ANALYSIS=PASS paths=$($inventory.Count) unique=$uniqueCount duplicates=$($inventory.Count-$uniqueCount) hash_reused=$hashCacheReused hash_recomputed=$hashRecomputed analyzed_unique=$analyzedUnique pending_unique=$($uniqueCount-$analyzedUnique) analyzed_paths=$analyzedPaths selected_unique=$($selectedGroups.Count) stale_cache=$staleCacheCount edges=$($edges.Count) missing=$($missing.Count) urls=$($allUrls.Count) runtime_observed_swfs=$($runtimeSwfByLeaf.Count) runtime_malformed_traces=$runtimeMalformedTraceCount runtime_prioritized_hashes=$($runtimePrioritizedHashes.Count) runtime_selected=$(@($selectedGroups | Where-Object { [int]$_.runtime_rank -lt 9 }).Count) runtime_trace=$($runtimeTrace.available) source_mutation=false root=$analysisRoot"
