[CmdletBinding()]
param([string]$RepoRoot = $env:GITHUB_WORKSPACE)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-GitBlobSha([string]$Path) {
  $payload=[IO.File]::ReadAllBytes($Path)
  $prefix=[Text.Encoding]::UTF8.GetBytes("blob $($payload.Length)`0")
  $all=New-Object byte[] ($prefix.Length+$payload.Length)
  [Buffer]::BlockCopy($prefix,0,$all,0,$prefix.Length)
  [Buffer]::BlockCopy($payload,0,$all,$prefix.Length,$payload.Length)
  $sha1=[Security.Cryptography.SHA1]::Create()
  try { return (($sha1.ComputeHash($all)|ForEach-Object{$_.ToString('x2')}) -join '') } finally { $sha1.Dispose() }
}
function Test-Swf([string]$Path) {
  $stream=[IO.File]::OpenRead($Path)
  try {
    if($stream.Length -lt 8){return $false}
    $head=New-Object byte[] 3
    if($stream.Read($head,0,3)-ne 3){return $false}
    return @('FWS','CWS','ZWS') -contains [Text.Encoding]::ASCII.GetString($head)
  } finally {$stream.Dispose()}
}

$commit='130504b8cbbba1666e31442f6ca27f6687157e63'
$url="https://raw.githubusercontent.com/CPImagined/CPImagined-Archive/$commit/default%20things/media1%20upload/media1.zip"
$expectedArchiveBytes=82987779
$expectedArchiveBlob='b2ba0e4767e4d93a3c86b541d9afa858317e9a19'
$tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('waddle-h15-client-probe-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot|Out-Null
$zipPath=Join-Path $tempRoot 'media1.zip'
try {
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zipPath -TimeoutSec 180
  $bytes=(Get-Item -LiteralPath $zipPath).Length
  $blob=Get-GitBlobSha $zipPath
  if($bytes -ne $expectedArchiveBytes -or $blob -ne $expectedArchiveBlob){
    throw "WADDLE_PARTY2015_CLIENT_ARCHIVE=FAIL bytes=$bytes blob=$blob expected_bytes=$expectedArchiveBytes expected_blob=$expectedArchiveBlob"
  }

  $wanted=@(
    [pscustomobject]@{name='intro_to_cp.swf';historicBytes=644934},
    [pscustomobject]@{name='intro_to_cp_quest_map.swf';historicBytes=138385}
  )
  $archive=[IO.Compression.ZipFile]::OpenRead($zipPath)
  try {
    foreach($item in $wanted){
      $needle=('play/v2/client/'+$item.name).ToLowerInvariant()
      $matches=@($archive.Entries|Where-Object{
        $entryName=$_.FullName.Replace('\','/').ToLowerInvariant()
        $entryName -eq $needle -or $entryName.EndsWith('/'+$needle)
      })
      if($matches.Count -eq 0){
        Write-Host "WADDLE_PARTY2015_CLIENT_ASSET_PROBE=NOT_FOUND name=$($item.name) archive_blob=$blob"
        continue
      }
      if($matches.Count -ne 1){throw "WADDLE_PARTY2015_CLIENT_ASSET_PROBE=FAIL name=$($item.name) matches=$($matches.Count)"}
      $entry=$matches[0]
      $out=Join-Path $tempRoot $item.name
      $input=$entry.Open(); $output=[IO.File]::Create($out)
      try {$input.CopyTo($output)} finally {$output.Dispose();$input.Dispose()}
      if(-not(Test-Swf $out)){throw "WADDLE_PARTY2015_CLIENT_ASSET_PROBE=FAIL invalid_swf=$($item.name)"}
      $assetBytes=(Get-Item -LiteralPath $out).Length
      $sha256=(Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash.ToLowerInvariant()
      $assetBlob=Get-GitBlobSha $out
      $historicMatch=($assetBytes -eq [long]$item.historicBytes)
      Write-Host "WADDLE_PARTY2015_CLIENT_ASSET_PROBE=FOUND name=$($item.name) entry=$($entry.FullName) bytes=$assetBytes sha256=$sha256 git_blob=$assetBlob historic_bytes=$($item.historicBytes) historic_match=$historicMatch archive_blob=$blob"
    }
  } finally {$archive.Dispose()}
} finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
