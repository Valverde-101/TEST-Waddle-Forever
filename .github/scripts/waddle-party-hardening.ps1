[CmdletBinding()]
param([string]$RepoRoot = $env:GITHUB_WORKSPACE)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$path = Join-Path $repo 'src/server/socket-server/world-handlers.ts'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$text = ([IO.File]::ReadAllText($path) -replace "`r`n", "`n")

$old = "    p.xt('s', 'party#qtupdate', ['number'], handlePartyTaskUpdate),"
$new = "    p.xt('s', 'party#qtupdate', ['number'], handlePartyTaskUpdate, { xt: { cooldown: 5000 } }),"
if ($text.Contains($old)) {
  $text = $text.Replace($old,$new)
} elseif (-not $text.Contains($new)) {
  throw 'WADDLE_PARTY_HARDENING=FAIL qtupdate_route_missing'
}

foreach ($route in @('party#partycookie','party#msgviewed','party#qcmsgviewed','party#qtaskcomplete','party#qtupdate')) {
  if (-not $text.Contains($route)) { throw "WADDLE_PARTY_HARDENING=FAIL missing_route=$route" }
}
if (-not $text.Contains("party#qtupdate', ['number'], handlePartyTaskUpdate, { xt: { cooldown: 5000 } }")) {
  throw 'WADDLE_PARTY_HARDENING=FAIL qtupdate_cooldown_missing'
}

[IO.File]::WriteAllText($path,$text,$utf8)
& git -C $repo add -- 'src/server/socket-server/world-handlers.ts'
if ($LASTEXITCODE -ne 0) { throw "WADDLE_PARTY_HARDENING=FAIL git_add_exit=$LASTEXITCODE" }
Write-Host 'WADDLE_PARTY_HARDENING=PASS qtupdate_cooldown_ms=5000 packet_cap=configurable staged=true'
