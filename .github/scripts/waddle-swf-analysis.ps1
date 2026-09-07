[CmdletBinding()]
param(
  [string]$RepoRoot,
  [string]$WorkRoot,
  [string]$FFDecPath,
  [ValidateRange(1,200)][int]$DeepBudget = 24,
  [ValidateRange(5,120)][int]$FFDecTimeoutSeconds = 25
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
New-Item -ItemType Directory -Force -Path $analysisRoot,$cacheRoot,$dumpRoot | Out-Null

function Get-RelativePath {
  param([Parameter(Mandatory)][string]$Base,[Parameter(Mandatory)][string]$Path)
  $baseUri = New-Object Uri(($Base.TrimEnd('\') + '\'))
  $pathUri = New-Object Uri($Path)
  return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/','\')
}

function Get-PrintableText {
  param([Parameter(Mandatory)][string]$Path)
  $bytes = [IO.File]::ReadAllBytes($Path)
  # Encoding.Latin1 is not available on every .NET Framework build used by
  # Windows PowerShell 5.1. ISO-8859-1 code page 28591 is byte-preserving for
  # the printable-string scan and works on the self-hosted runner.
  $text = [Text.Encoding]::GetEncoding(28591).GetString($bytes)
  return [regex]::Replace($text, '[^\x20-\x7E\r\n\t]', ' ')
}

function Get-ReferenceData {
  param([Parameter(Mandatory)][string]$Text)
  $urls = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
  $swfs = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
  $protocols = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)

  foreach ($m in [regex]::Matches($Text, '(?i)\b(?:https?|wss?|rtmp|socket)://[^\s"''<>]+')) {
    $value = $m.Value.TrimEnd(')',']','}',',',';')
    [void]$urls.Add($value)
    $scheme = $value.Split(':')[0].ToLowerInvariant()
    [void]$protocols.Add($scheme)
  }
  foreach ($m in [regex]::Matches($Text, '(?i)(?:[A-Za-z0-9_@%+=:,./-]+)?[A-Za-z0-9_@%+=,-]+\.swf(?:\?[^\s"''<>]*)?')) {
    $value = $m.Value.Replace('/','\').TrimStart('.','\')
    if ($value.Length -le 512) { [void]$swfs.Add($value) }
  }
  foreach ($token in @('XMLSocket','Socket','SmartFox','RTMP','WebSocket')) {
    if ($Text -match ('(?i)\b' + [regex]::Escape($token) + '\b')) { [void]$protocols.Add($token.ToLowerInvariant()) }
  }
  [pscustomobject]@{
    urls = @($urls | Sort-Object)
    swf_refs = @($swfs | Sort-Object)
    protocols = @($protocols | Sort-Object)
  }
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
  $proc = Start-Process -FilePath $FFDec -ArgumentList @('-cli',$arg,$quotedSwf) -RedirectStandardOutput $OutFile -RedirectStandardError $ErrFile -PassThru -WindowStyle Hidden
  if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    try { $proc.Kill() } catch {}
    try { [void]$proc.WaitForExit(5000) } catch {}
    return [pscustomobject]@{ status='TIMEOUT'; exit=-1; output=$OutFile; error=$ErrFile }
  }
  $proc.Refresh()
  return [pscustomobject]@{ status=($(if ($proc.ExitCode -eq 0) {'PASS'} else {'FAIL'})); exit=[int]$proc.ExitCode; output=$OutFile; error=$ErrFile }
}

if (-not $FFDecPath) {
  if ($env:FFDEC_PATH) { $FFDecPath = $env:FFDEC_PATH }
  elseif ($env:WADDLE_FFDEC) { $FFDecPath = $env:WADDLE_FFDEC }
}
if (-not $FFDecPath -or -not (Test-Path -LiteralPath $FFDecPath -PathType Leaf)) {
  throw "WADDLE_SWF_ANALYSIS=FAIL ffdec_missing path=$FFDecPath"
}
$FFDecPath = [IO.Path]::GetFullPath($FFDecPath)

$scanRoots = @()
foreach ($candidate in @((Join-Path $RepoRoot 'media'),(Join-Path $RepoRoot 'assets'))) {
  if (Test-Path -LiteralPath $candidate -PathType Container) { $scanRoots += $candidate }
}
$swfFiles = @($scanRoots | ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter '*.swf' -File -Recurse -ErrorAction SilentlyContinue } | Sort-Object FullName -Unique)

$inventory = New-Object System.Collections.Generic.List[object]
$byLeaf = @{}
$byRelative = @{}
foreach ($file in $swfFiles) {
  $relative = Get-RelativePath -Base $RepoRoot -Path $file.FullName
  $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  $item = [pscustomobject]@{
    path = $relative
    sha256 = $hash
    size = [int64]$file.Length
    modified_utc = $file.LastWriteTimeUtc.ToString('o')
  }
  $inventory.Add($item)
  $leaf = $file.Name.ToLowerInvariant()
  if (-not $byLeaf.ContainsKey($leaf)) { $byLeaf[$leaf] = New-Object System.Collections.Generic.List[string] }
  $byLeaf[$leaf].Add($relative)
  $byRelative[$relative.Replace('/','\').ToLowerInvariant()] = $relative
}

$deepCandidates = @($inventory | Sort-Object @{Expression={ if ([IO.Path]::GetFileName($_.path) -ieq 'boots.swf') {0} elseif (-not (Test-Path -LiteralPath (Join-Path $cacheRoot ($_.sha256 + '.json')))) {1} else {2} }}, path)
$selected = @($deepCandidates | Select-Object -First $DeepBudget)
$selectedHashes = @($selected | ForEach-Object { [string]$_.sha256 })
$results = New-Object System.Collections.Generic.List[object]
$allUrls = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
$allProtocols = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
$edges = New-Object System.Collections.Generic.List[object]
$missing = New-Object System.Collections.Generic.List[object]

foreach ($item in $inventory) {
  $cachePath = Join-Path $cacheRoot ($item.sha256 + '.json')
  $deep = $selectedHashes -contains $item.sha256
  $analysis = $null
  if ((-not $deep) -and (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
    try { $analysis = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json } catch { $analysis = $null }
  }

  if (-not $analysis) {
    $full = Join-Path $RepoRoot $item.path
    $binaryText = Get-PrintableText -Path $full
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add($binaryText)
    $ffdecRuns = @()
    if ($deep) {
      foreach ($kind in @('AS2','AS3')) {
        $prefix = Join-Path $dumpRoot ($item.sha256 + '.' + $kind.ToLowerInvariant())
        $run = Invoke-FFDecDump -FFDec $FFDecPath -Kind $kind -Swf $full -OutFile ($prefix + '.txt') -ErrFile ($prefix + '.stderr.txt') -TimeoutSeconds $FFDecTimeoutSeconds
        $ffdecRuns += [pscustomobject]@{ kind=$kind; status=$run.status; exit=$run.exit }
        if (Test-Path -LiteralPath $run.output -PathType Leaf) {
          try { $parts.Add((Get-Content -LiteralPath $run.output -Raw -ErrorAction Stop)) } catch {}
        }
      }
    }
    $refs = Get-ReferenceData -Text ($parts -join "`n")
    $analysis = [pscustomobject]@{
      schema = 'waddle-swf-analysis-item/v1'
      path = $item.path
      sha256 = $item.sha256
      size = $item.size
      deep = [bool]$deep
      ffdec = @($ffdecRuns)
      urls = @($refs.urls)
      protocols = @($refs.protocols)
      swf_refs = @($refs.swf_refs)
      analyzed_utc = [DateTime]::UtcNow.ToString('o')
    }
    if ($deep) { $analysis | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $cachePath -Encoding UTF8 }
  }

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
  $results.Add($analysis)
}

$probePath = Join-Path $WorkRoot 'state\flash-runtime-probe.json'
$runtimeTrace = [ordered]@{
  schema = 'waddle-swf-runtime-trace/v1'
  source = $probePath
  available = $false
  production_url = $null
  observed_responses = @()
  renderer = $null
}
if (Test-Path -LiteralPath $probePath -PathType Leaf) {
  try {
    $probe = Get-Content -LiteralPath $probePath -Raw | ConvertFrom-Json
    $runtimeTrace.available = $true
    $runtimeTrace.production_url = $probe.production_url
    $runtimeTrace.observed_responses = @($probe.observed_responses)
    $runtimeTrace.renderer = $probe.renderer
  } catch {}
}

$coverage = @($results | Where-Object { $_.deep -or (Test-Path -LiteralPath (Join-Path $cacheRoot ($_.sha256 + '.json')))}).Count
$summary = [ordered]@{
  schema = 'waddle-swf-analysis/v1'
  status = 'PASS'
  repository_root = $RepoRoot
  ffdec = $FFDecPath
  source_mutation = $false
  swf_count = $inventory.Count
  deep_budget = $DeepBudget
  deep_selected = $selected.Count
  cached_or_deep_count = $coverage
  dependency_edges = $edges.Count
  unresolved_literal_refs = $missing.Count
  url_count = $allUrls.Count
  protocols = @($allProtocols | Sort-Object)
  runtime_trace_available = [bool]$runtimeTrace.available
  generated_utc = [DateTime]::UtcNow.ToString('o')
}

$inventory | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $analysisRoot 'manifest.json') -Encoding UTF8
$results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $analysisRoot 'items.json') -Encoding UTF8
$edges | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $analysisRoot 'dependency-graph.json') -Encoding UTF8
@($allUrls | Sort-Object) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $analysisRoot 'urls.json') -Encoding UTF8
$missing | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $analysisRoot 'missing-swfs.json') -Encoding UTF8
$runtimeTrace | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $analysisRoot 'runtime-trace.json') -Encoding UTF8
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $analysisRoot 'summary.json') -Encoding UTF8

Write-Host "WADDLE_SWF_ANALYSIS=PASS swfs=$($inventory.Count) deep_selected=$($selected.Count) covered=$coverage edges=$($edges.Count) missing=$($missing.Count) urls=$($allUrls.Count) runtime_trace=$($runtimeTrace.available) source_mutation=false root=$analysisRoot"
