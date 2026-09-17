[CmdletBinding()]
param(
  [string]$RepoRoot = $env:GITHUB_WORKSPACE,
  [string]$FFDecPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-FFDec([string]$Explicit) {
  if ($Explicit -and (Test-Path -LiteralPath $Explicit -PathType Leaf)) { return (Resolve-Path -LiteralPath $Explicit).Path }
  foreach ($candidate in @($env:FFDEC_PATH,$env:WADDLE_FFDEC)) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return (Resolve-Path -LiteralPath $candidate).Path }
  }
  $root = 'V:\AndroidBuild\Tools\FFDec'
  $exe = Get-ChildItem -LiteralPath $root -Filter 'ffdec-cli.exe' -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
  if ($exe) { return $exe.FullName }
  throw 'WADDLE_PARTY2015_API_PROBE=FAIL ffdec_missing'
}

function Export-Text([string]$FFDec,[string]$Swf,[string]$Name,[string]$Work) {
  if (-not (Test-Path -LiteralPath $Swf -PathType Leaf)) { throw "WADDLE_PARTY2015_API_PROBE=FAIL missing=$Name" }
  $out = Join-Path $Work ($Name + '-scripts')
  New-Item -ItemType Directory -Force -Path $out | Out-Null
  $stdout = Join-Path $Work ($Name + '.stdout.txt')
  $stderr = Join-Path $Work ($Name + '.stderr.txt')
  $args = @('-cli','-onerror','ignore','-exportTimeout','60','-exportFileTimeout','20','-export','script',('"' + $out + '"'),('"' + $Swf + '"'))
  $proc = Start-Process -FilePath $FFDec -ArgumentList $args -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
  if (-not $proc.WaitForExit(120000)) { try { $proc.Kill() } catch {}; throw "WADDLE_PARTY2015_API_PROBE=FAIL timeout=$Name" }
  $proc.Refresh()
  if ([int]$proc.ExitCode -ne 0) { throw "WADDLE_PARTY2015_API_PROBE=FAIL ffdec_exit=$($proc.ExitCode) name=$Name" }
  $files = @(Get-ChildItem -LiteralPath $out -File -Recurse | Where-Object { $_.Extension -in @('.as','.txt') } | Sort-Object FullName)
  $parts = @()
  foreach ($file in $files) {
    $body = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if ($body) { $parts += "// FILE: $($file.FullName.Substring($out.Length).TrimStart('\\'))`n$body" }
  }
  return [pscustomobject]@{ files=$files.Count; text=($parts -join "`n") }
}

function Unique-Matches([string]$Text,[string]$Pattern,[int]$Group=1) {
  $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($m in [regex]::Matches($Text,$Pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
    [void]$set.Add($m.Groups[$Group].Value)
  }
  return @($set | Sort-Object)
}

function Emit-Snippet([string]$Name,[string]$Text,[string]$Pattern) {
  $lines=@($Text -split "`r?`n")
  for($i=0;$i -lt $lines.Count;$i++) {
    if($lines[$i] -match $Pattern) {
      $start=[Math]::Max(0,$i-4);$end=[Math]::Min($lines.Count-1,$i+10)
      $snippet=[regex]::Replace(($lines[$start..$end]-join ' '),'\s+',' ')
      if($snippet.Length -gt 2200){$snippet=$snippet.Substring(0,2200)}
      Write-Host "WADDLE_PARTY2015_API_EVIDENCE name=$Name text=$snippet"
      return
    }
  }
  Write-Host "WADDLE_PARTY2015_API_EVIDENCE name=$Name text=MISSING"
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$root = Join-Path $repo 'media\default\party2015'
$ffdec = Resolve-FFDec $FFDecPath
$work = Join-Path $repo '.work\halloween2015-api-probe'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null

$party = Export-Text $ffdec (Join-Path $root 'content\party-base-2015.swf') 'party-base' $work
$features = Export-Text $ffdec (Join-Path $root 'content\ContentFeatures-HalloweenParty2015.swf') 'features' $work
$quest = Export-Text $ffdec (Join-Path $root 'close_ups\Close_upsQuest_interface-HalloweenParty2015.swf') 'quest-interface' $work
$login = Export-Text $ffdec (Join-Path $root 'close_ups\Hallo15_dialogue_login.swf') 'login-dialogue' $work
$communicator = Export-Text $ffdec (Join-Path $root 'client\QuestCommunicator.swf') 'quest-communicator' $work

$partyClasses = Unique-Matches $party.text '(?:class|new)\s+([A-Za-z0-9_\.]+)'
$currentPartyMembers = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($pattern in @(
  '(?:_currentParty|_currentparty)\.([A-Za-z_][A-Za-z0-9_]*)',
  'CURRENT_PARTY\.([A-Za-z_][A-Za-z0-9_]*)'
)) {
  foreach ($name in (Unique-Matches $quest.text $pattern)) { [void]$currentPartyMembers.Add($name) }
}

$featureCalls = Unique-Matches $features.text '(?:_currentParty|CURRENT_PARTY)\.([A-Za-z_][A-Za-z0-9_]*)'
$loginCalls = Unique-Matches $login.text '(?:CURRENT_PARTY|_currentParty|_currentparty)\.([A-Za-z_][A-Za-z0-9_]*)'
$loginPackets = Unique-Matches $login.text '["'']([A-Za-z0-9_]+#[A-Za-z0-9_]+)["'']'
$communicatorNames = Unique-Matches $communicator.text '(?:class|new)\s+([A-Za-z0-9_\.]*Quest[A-Za-z0-9_\.]*)'

$classChecks = [ordered]@{
  partyJsonParser = [bool]($party.text -match '(?i)PartyJSON_Parser')
  partyFeaturesVO = [bool]($party.text -match '(?i)PartyFeature|PartyFeatures|featureSettings')
  questTaskVO = [bool]($party.text -match '(?i)QuestTaskVO|QuestVO')
  transformationVO = [bool]($party.text -match '(?i)TransformationVO')
  puffleAdoptionVO = [bool]($party.text -match '(?i)PuffleAdoptionVO')
  jsonParser = [bool]($party.text -match '(?i)JSONParser')
  mayPartySendMessageViewed = [bool]($party.text -match '(?i)static function sendMessageViewed')
  mayPartyLoadFeatures = [bool]($party.text -match '(?i)static function loadPartyFeatures')
  mayPartyConfigureFeatures = [bool]($party.text -match '(?i)static function configurePartyJSON')
}

Write-Host "WADDLE_PARTY2015_API_COMPONENT=party-base scripts=$($party.files)"
foreach ($kv in $classChecks.GetEnumerator()) { Write-Host "WADDLE_PARTY2015_API_CLASS key=$($kv.Key) present=$($kv.Value)" }
foreach ($member in @($currentPartyMembers | Sort-Object)) { Write-Host "WADDLE_PARTY2015_API_QUEST_MEMBER=$member" }
foreach ($member in $featureCalls) { Write-Host "WADDLE_PARTY2015_API_FEATURE_CALL=$member" }
foreach ($member in $loginCalls) { Write-Host "WADDLE_PARTY2015_API_LOGIN_CALL=$member" }
foreach ($packet in $loginPackets) { Write-Host "WADDLE_PARTY2015_API_LOGIN_PACKET=$packet" }
foreach ($name in $communicatorNames) { Write-Host "WADDLE_PARTY2015_API_COMMUNICATOR_SYMBOL=$name" }

# The live trace proves the login asset jumps to shack but emits no msgviewed.
# Print its exact completion code so any server/client fix is evidence-based.
Emit-Snippet 'login_sendMessageViewed' $login.text '(?i)sendMessageViewed|setMessageViewed|msgviewed'
Emit-Snippet 'login_joinRoom' $login.text '(?i)sendJoinRoom|joinRoom|shack'
Emit-Snippet 'login_closeContent' $login.text '(?i)closeContent|onRelease|close_btn|closeButton'
Emit-Snippet 'mayparty_sendMessageViewed' $party.text '(?i)static function sendMessageViewed'
Emit-Snippet 'mayparty_icon_visible' $party.text '(?i)partyIconVisible'

$loginHasViewed = [bool]($login.text -match '(?i)sendMessageViewed|setMessageViewed|msgviewed|MESSAGE_VIEWED')
$featuresCallsLoad = [bool]($features.text -match '(?i)loadPartyFeatures')
if (-not $featuresCallsLoad) { throw 'WADDLE_PARTY2015_API_PROBE=FAIL features_missing_loadPartyFeatures_call' }

$summary = [ordered]@{
  schema='waddle-halloween2015-api-probe/v2'
  classChecks=$classChecks
  questMembers=@($currentPartyMembers | Sort-Object)
  featureCalls=$featureCalls
  loginCalls=$loginCalls
  loginPackets=$loginPackets
  loginHasViewed=$loginHasViewed
  communicatorSymbols=$communicatorNames
}
$summaryPath = Join-Path $work 'summary.json'
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "WADDLE_PARTY2015_API_PROBE=PASS features_calls_load=$featuresCallsLoad login_has_viewed=$loginHasViewed quest_members=$($currentPartyMembers.Count) summary=$summaryPath"
