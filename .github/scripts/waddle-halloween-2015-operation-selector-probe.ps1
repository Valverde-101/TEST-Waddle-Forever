[CmdletBinding()]
param([string]$RepoRoot=$env:GITHUB_WORKSPACE,[string]$FFDecPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Resolve-FFDec([string]$Explicit){
  if($Explicit -and (Test-Path -LiteralPath $Explicit -PathType Leaf)){return (Resolve-Path $Explicit).Path}
  foreach($candidate in @($env:FFDEC_PATH,$env:WADDLE_FFDEC)){if($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)){return (Resolve-Path $candidate).Path}}
  $exe=Get-ChildItem 'V:\AndroidBuild\Tools\FFDec' -Filter 'ffdec-cli.exe' -File -Recurse -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1
  if($exe){return $exe.FullName}; throw 'WADDLE_PARTY2015_OPERATION_SELECTOR=FAIL ffdec_missing'
}
$repo=(Resolve-Path $RepoRoot).Path
$work=Join-Path $repo '.work\halloween2015-operation-selector'
if(Test-Path $work){Remove-Item $work -Recurse -Force}; New-Item -ItemType Directory -Force -Path $work|Out-Null
$name='ClientParty-OperationCrustacean.swf'
$url='https://toolbox.solero.me/cparchives/static/images/archives/a/ae/ClientParty-OperationCrustacean.swf'
$swf=Join-Path $work $name
Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $swf -TimeoutSec 120 -Headers @{'User-Agent'='Waddle-Forever-Halloween2015-Probe/1.0'}
$out=Join-Path $work 'scripts'; New-Item -ItemType Directory -Force -Path $out|Out-Null
$ffdec=Resolve-FFDec $FFDecPath
$stdout=Join-Path $work 'ffdec.stdout.txt'; $stderr=Join-Path $work 'ffdec.stderr.txt'
$args=@('-cli','-onerror','ignore','-exportTimeout','60','-exportFileTimeout','20','-export','script',('"'+$out+'"'),('"'+$swf+'"'))
$proc=Start-Process -FilePath $ffdec -ArgumentList $args -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
if(-not $proc.WaitForExit(120000)){try{$proc.Kill()}catch{};throw 'WADDLE_PARTY2015_OPERATION_SELECTOR=FAIL ffdec_timeout'}
$proc.Refresh();if([int]$proc.ExitCode -ne 0){throw "WADDLE_PARTY2015_OPERATION_SELECTOR=FAIL ffdec_exit=$($proc.ExitCode)"}
$files=@(Get-ChildItem $out -File -Recurse|Where-Object{$_.Extension -in @('.as','.txt')})
$text=($files|ForEach-Object{Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue}) -join "`n"
$selectors=New-Object 'System.Collections.Generic.HashSet[string]'
foreach($m in [regex]::Matches($text,'(?<!\d)20\d{6}(?!\d)')){[void]$selectors.Add($m.Value)}
foreach($s in @($selectors|Sort-Object)){Write-Host "WADDLE_PARTY2015_OPERATION_SELECTOR_TOKEN=$s"}
$patterns=@('handleGetActiveFeatures','activeFeaturesArray','AutomatedParty.init','PARTY_COOKIE_ID','configurePartyJSON','FEATURES_SWF_PATH')
$lines=@($text -split "`r?`n")
foreach($pattern in $patterns){
  for($i=0;$i -lt $lines.Count;$i++){
    if($lines[$i] -match [regex]::Escape($pattern)){
      $start=[Math]::Max(0,$i-3);$end=[Math]::Min($lines.Count-1,$i+5)
      $snippet=[regex]::Replace(($lines[$start..$end]-join ' '),'\s+',' ')
      if($snippet.Length -gt 1200){$snippet=$snippet.Substring(0,1200)}
      Write-Host "WADDLE_PARTY2015_OPERATION_SELECTOR_EVIDENCE pattern=$pattern text=$snippet"
      break
    }
  }
}
Write-Host "WADDLE_PARTY2015_OPERATION_SELECTOR=PASS selectors=$(@($selectors|Sort-Object)-join ',') scripts=$($files.Count) sha256=$((Get-FileHash $swf -Algorithm SHA256).Hash.ToLowerInvariant()) bytes=$((Get-Item $swf).Length)"
