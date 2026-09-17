param([string]$RepoRoot=$env:GITHUB_WORKSPACE,[string]$CanonicalRoot=$RepoRoot)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw "WADDLE_PARTY2015_VERIFY=FAIL $Message"}}
function Test-Swf([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $false};$s=[IO.File]::OpenRead($Path);try{if($s.Length-lt 8){return $false};$b=New-Object byte[] 3;if($s.Read($b,0,3)-ne 3){return $false};return @('FWS','CWS','ZWS')-contains[Text.Encoding]::ASCII.GetString($b)}finally{$s.Dispose()}}
function Get-GitBlobSha([string]$Path){$p=[IO.File]::ReadAllBytes($Path);$h=[Text.Encoding]::UTF8.GetBytes("blob $($p.Length)`0");$a=New-Object byte[]($h.Length+$p.Length);[Buffer]::BlockCopy($h,0,$a,0,$h.Length);[Buffer]::BlockCopy($p,0,$a,$h.Length,$p.Length);$s=[Security.Cryptography.SHA1]::Create();try{return(($s.ComputeHash($a)|ForEach-Object{$_.ToString('x2')})-join'')}finally{$s.Dispose()}}
function Match([string]$Text,[string]$Pattern,[string]$Message){Assert ($Text-match$Pattern) $Message}
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$canonical=(Resolve-Path -LiteralPath $CanonicalRoot).Path
$updates=[IO.File]::ReadAllText((Join-Path $repo 'src/server/updates/2015.ts'))
$generators=[IO.File]::ReadAllText((Join-Path $repo 'src/server/file-generators/index.ts'))
$xt=[IO.File]::ReadAllText((Join-Path $repo 'src/server/socket-server/xt-handler.ts'))
$assetRoot=Join-Path $canonical 'media/default/party2015'
$manifest=Get-Content -LiteralPath (Join-Path $assetRoot 'manifest.json') -Raw|ConvertFrom-Json
$canonicalManifest=Get-Content -LiteralPath (Join-Path $repo '.github/manifests/halloween-2015-canonical.json') -Raw|ConvertFrom-Json

Match $updates "date\s*:\s*'2015-10-21'" 'party_start_missing'
Match $updates "partyName\s*:\s*'Halloween Party 2015'" 'party_name_missing'
Match $updates "activeFeatures\s*:\s*'20151101'" 'templated_selector_missing'
Match $updates "partyEndDate\s*:\s*'2015-11-05 00:00:00'" 'partyservice_end_missing'
Match $updates "date\s*:\s*'2015-11-05'[\s\S]*?end\s*:\s*\['party'\]" 'party_end_missing'
foreach($entry in @{
 runtime="'play/v2/content/global/content/party\.swf'\s*:\s*ref\('content/party-runtime-2015\.swf'\)";
 shell="'play/v2/client/shell\.swf'\s*:\s*'svanilla:media/play/v2/client/shell\.swf'";
 questcomm="'play/v2/client/QuestCommunicator\.swf'\s*:\s*ref\('client/QuestCommunicator\.swf'\)";
 interface="'play/v2/content/global/content/interface\.swf'\s*:\s*ref\('client/ClientInterface-HalloweenParty2015\.swf'\)";
 features="'play/v2/content/global/content/features\.swf'\s*:\s*ref\('content/ContentFeatures-HalloweenParty2015\.swf'\)";
 icon="'play/v2/content/global/content/party_icon\.swf'\s*:\s*ref\('content/ContentParty_icon-HalloweenParty2015\.swf'\)";
 login="'close_ups/halloLogin\.swf'\s*:\s*\[ref\('close_ups/Hallo15_dialogue_login\.swf'\).*?'w\.app\.loginprompt'";
 quest="'close_ups/quest_interface\.swf'\s*:\s*\[ref\('close_ups/Close_upsQuest_interface-HalloweenParty2015\.swf'\).*?'w\.app\.generic\.partyinterface'"
}.GetEnumerator()){Match $updates $entry.Value ('live_'+$entry.Key)}
Assert (-not $updates.Contains("ref('content/party-base-2015.swf')")) 'obsolete_mayparty_runtime_live'
Assert (-not $updates.Contains("ref('content/party.swf')")) 'recreation_party_runtime_live'
Assert (-not $updates.Contains("ref('content/map.swf')")) 'unverified_recreation_map_live'
Assert ($xt.Contains("['s%party#transform', 's%pt#spts']")) 'party_transform_alias_missing'

Assert ($generators.Contains("const HALLOWEEN_2015_SOLO_ROOM_ROUTE = 'play/v2/content/global/rooms/partysolo1.swf';")) 'solo_room_guard_missing'
Match $generators "rooms\['891'\]\s*=\s*\{" 'solo_room_891_missing'
Match $generators "room_key\s*:\s*'partysolo1'" 'solo_room_key_missing'

Assert ([int]$manifest.requiredCount -eq 132) "historical_required=$($manifest.requiredCount)"
$historical=@($manifest.assets|Where-Object{[bool]$_.required});Assert ($historical.Count-eq132) "historical_entries=$($historical.Count)"
$historicalTargets=New-Object 'System.Collections.Generic.HashSet[string]'([StringComparer]::OrdinalIgnoreCase)
foreach($entry in $historical){$relative=([string]$entry.relativePath).Replace('\','/');Assert($historicalTargets.Add($relative))"duplicate_historical=$relative";$path=Join-Path $assetRoot $relative.Replace('/','\');Assert(Test-Swf $path)"historical_invalid=$relative";$item=Get-Item -LiteralPath $path;Assert([int64]$item.Length-eq[int64]$entry.bytes)"historical_bytes=$relative";$sha=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant();Assert($sha-eq([string]$entry.sha256).ToUpperInvariant())"historical_sha=$relative"}
foreach($critical in @('client/ClientInterface-HalloweenParty2015.swf','close_ups/Close_upsQuest_interface-HalloweenParty2015.swf','content/ContentFeatures-HalloweenParty2015.swf','content/ContentParty_icon-HalloweenParty2015.swf','rooms/Hallo15_partysolo1.swf')){Assert($historicalTargets.Contains($critical))"historical_missing=$critical"}

Assert ($canonicalManifest.schema-eq'waddle-canonical-assets/v1') 'canonical_schema'
$canonicalAssets=@($canonicalManifest.assets);$canonicalTargets=New-Object 'System.Collections.Generic.HashSet[string]'([StringComparer]::OrdinalIgnoreCase);$canonicalSwfs=0
foreach($entry in $canonicalAssets){$target=([string]$entry.target).Replace('\','/');Assert($canonicalTargets.Add($target))"duplicate_canonical=$target";$path=Join-Path $assetRoot $target.Replace('/','\');Assert(Test-Path -LiteralPath $path -PathType Leaf)"canonical_missing=$target";Assert([int64](Get-Item $path).Length-eq[int64]$entry.bytes)"canonical_bytes=$target";if($entry.PSObject.Properties.Name-contains'sha256'-and-not[string]::IsNullOrWhiteSpace([string]$entry.sha256)){$actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();Assert($actual-eq([string]$entry.sha256).ToLowerInvariant())"canonical_sha256=$target"}else{Assert((Get-GitBlobSha $path)-eq([string]$entry.gitBlobSha).ToLowerInvariant())"canonical_blob=$target"};if([string]$entry.kind-eq'swf'){$canonicalSwfs++;Assert(Test-Swf $path)"canonical_swf=$target"}}
Assert($canonicalTargets.Contains('content/party-runtime-2015.swf'))'templated_runtime_missing'
$runtime=$canonicalAssets|Where-Object{$_.target-eq'content/party-runtime-2015.swf'}|Select-Object -First 1;Assert([long]$runtime.bytes-eq39406)'runtime_bytes';Assert(([string]$runtime.sha256).ToLowerInvariant()-eq'd30fcd85c2f4a6b9ef6d1b81aac3a6d2f592af5f68ae13bb9d1564cb5b115cf7')'runtime_sha256'

$physicalSwfs=@(Get-ChildItem -LiteralPath $assetRoot -Filter '*.swf' -File -Recurse);$expected=$historical.Count+$canonicalSwfs;Assert($physicalSwfs.Count-eq$expected)"physical_swfs=$($physicalSwfs.Count) expected=$expected"
Write-Host "WADDLE_PARTY2015_VERIFY=PASS runtime=templated-late-2015 activefeatures=20151101 shell=svanilla historical_verified=132 canonical_provenance=$($canonicalAssets.Count) canonical_swfs=$canonicalSwfs solo_room=891 transform=party-to-spts"
