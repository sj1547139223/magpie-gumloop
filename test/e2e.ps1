# End-to-end test of the plugin in a real magpie against test/mock-gumloop.mjs,
# in a fresh sandbox (.sandbox-mock): your own magpie and sign-ins are not touched.
#   .\test\e2e.ps1
# MAGPIE is the magpie binary (default: magpie on PATH).
# Continue: PowerShell 5.1 turns a native command's stderr into an error under
# Stop, and the checks below read exit codes themselves.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$sb = Join-Path $root '.sandbox-mock'
$mockPort = 4811
$gw = '127.0.0.1:3498'
$magpie = if ($env:MAGPIE) { $env:MAGPIE } else { 'magpie' }
$mockSrc = Get-Content -Raw (Join-Path $PSScriptRoot 'mock-gumloop.mjs')
$key = [regex]::Match($mockSrc, 'KEY = "([^"]+)"').Groups[1].Value
$user = [regex]::Match($mockSrc, 'USER = "([^"]+)"').Groups[1].Value
$mock = "http://127.0.0.1:$mockPort"

if (Test-Path $sb) { Remove-Item -Recurse -Force $sb }
New-Item -ItemType Directory -Force $sb | Out-Null
$env:HOME = $sb; $env:USERPROFILE = $sb; $env:XDG_CONFIG_HOME = "$sb\.config"; $env:XDG_CACHE_HOME = "$sb\.cache"; $env:MAGPIE_ADDR = $gw
$env:GUMLOOP_API_BASE = "$mock/api"; $env:GUMLOOP_WS_BASE = "$mock/ws"; $env:GUMLOOP_OPENROUTER_BASE = "$mock/or"

$script:failed = 0
function Check($name, $ok, $detail = '') {
  if ($ok) { Write-Output "  ok    $name" } else { $script:failed++; Write-Output "  FAIL  $name $detail" }
}
function Mock($path, $body) {
  if ($body) { Invoke-RestMethod -Method Post -Uri "$mock$path" -Body ($body | ConvertTo-Json -Compress) -ContentType 'application/json' }
  else { Invoke-RestMethod -Uri "$mock$path" }
}
function Chat($model, $extra = @{}) {
  $body = @{ model = $model; messages = @(@{ role = 'user'; content = 'hi' }) } + $extra
  try {
    $r = Invoke-WebRequest -UseBasicParsing -Method Post -Uri "http://$gw/v1/chat/completions" -Body ($body | ConvertTo-Json -Depth 5 -Compress) -ContentType 'application/json' -TimeoutSec 60
    return @{ status = [int]$r.StatusCode; body = $r.Content }
  } catch [System.Net.WebException] {
    $resp = $_.Exception.Response
    if (-not $resp) { return @{ status = 0; body = $_.Exception.Message } }
    $text = (New-Object System.IO.StreamReader($resp.GetResponseStream())).ReadToEnd()
    return @{ status = [int]$resp.StatusCode; body = $text }
  }
}
function Quota {
  $out = & $magpie quota gumloop --json 2>$null | Out-String
  try { $q = $out | ConvertFrom-Json } catch { return @{ error = "not JSON: $out" } }
  return @($q | Where-Object { $_.provider -eq 'gumloop' })[0]
}

$mockProc = Start-Process node -ArgumentList "`"$PSScriptRoot\mock-gumloop.mjs`" $mockPort" -PassThru -WindowStyle Hidden
$serve = $null
try {
  Start-Sleep -Milliseconds 800

  Write-Output '--- add and sign in'
  & $magpie plugin add (Join-Path $root 'packages\gumloop') 2>&1 | Out-Null
  "badkey`n$user`n`n`n" | & $magpie plugin login gumloop 2>&1 | Out-Null
  Check 'a wrong key is refused at sign-in' ($LASTEXITCODE -ne 0)
  "$key`n$user`nmock@example.com`n5000`n" | & $magpie plugin login gumloop 2>&1 | Out-Null
  Check 'sign-in succeeds' ($LASTEXITCODE -eq 0)
  $list = & $magpie plugin 2>&1 | Out-String
  Check 'the account lists its models' ($list -match 'gumloop \(Gumloop, 4 models\)\s+signed in as mock@example.com') $list
  $auth = Get-Content -Raw "$sb\.config\magpie\plugin-auth.json" | ConvertFrom-Json
  Check 'the key is not copied into metadata' (-not ($auth.gumloop.metadata.PSObject.Properties.Name -contains 'key'))

  Write-Output '--- provider test'
  $t = & $magpie provider test gumloop 2>&1 | Out-String
  Check 'provider test passes' ($LASTEXITCODE -eq 0 -and $t -match 'chat') $t

  Write-Output '--- gateway'
  $serve = Start-Process $magpie -ArgumentList 'serve' -PassThru -WindowStyle Hidden
  for ($i = 0; $i -lt 40; $i++) { & $magpie healthcheck 2>&1 | Out-Null; if ($LASTEXITCODE -eq 0) { break }; Start-Sleep -Milliseconds 250 }
  Check 'gateway is up' ($LASTEXITCODE -eq 0)
  Mock '/_reset' @{} | Out-Null

  $r = Chat 'gumloop/claude-sonnet-5-5'
  Check 'non-streaming chat' ($r.status -eq 200 -and $r.body -match 'pong from claude-sonnet-5-5') "$($r.status) $($r.body)"
  $r = Chat 'gumloop/claude-sonnet-5-5' @{ stream = $true }
  Check 'streaming chat' ($r.status -eq 200 -and $r.body -match 'pong') "$($r.status) $($r.body)"
  Mock '/_mode' @{ mode = 'octet-stream' } | Out-Null
  $r = Chat 'gumloop/claude-sonnet-5-5' @{ stream = $true }
  Check 'streaming with an octet-stream content type' ($r.status -eq 200 -and $r.body -match 'pong') "$($r.status) $($r.body)"
  Mock '/_mode' @{ mode = 'ok' } | Out-Null
  $r = Chat 'gumloop/gpt-6-sol' @{ max_completion_tokens = 50; store = $true; reasoning_effort = 'high' }
  Check 'gpt chat' ($r.status -eq 200) "$($r.status) $($r.body)"
  $r = Chat 'gumloop/glm-5p3'
  Check 'aliased model (glm-5p3) is served' ($r.status -eq 200 -and $r.body -match 'accounts/fireworks/models/glm-5p3') "$($r.status) $($r.body)"
  $r = Chat 'gumloop/claude-sonnet-5-5' @{ max_tokens = 100000 }
  Check 'a too-large max_tokens is learned and retried' ($r.status -eq 200) "$($r.status) $($r.body)"

  $log = @(Mock '/_log')
  $sent = @($log | ForEach-Object { $_.body })
  Check 'every request carries the user id' (@($log | Where-Object { $_.headers.'x-auth-key' -ne $user }).Count -eq 0)
  Check 'claude does not opt into a 1h cache by default' ($null -eq $sent[0].cache_control)
  Check 'usage is asked for when streaming' ($sent[1].stream_options.include_usage -eq $true)
  $gpt = @($sent | Where-Object { $_.model -eq 'gpt-6-sol' })[0]
  Check 'gpt body is normalized' ($gpt.max_tokens -eq 50 -and $null -eq $gpt.max_completion_tokens -and $null -eq $gpt.store -and $gpt.reasoning.effort -eq 'high') ($gpt | ConvertTo-Json -Compress)
  # magpie may itself ask for the model's whole output limit when a client
  # names none, so the call that meets the vendor's cap isn't always the same
  $sonnet = @($sent | Where-Object { $_.model -eq 'claude-sonnet-5-5' } | ForEach-Object { [int]$_.max_tokens })
  $first = [array]::FindIndex([int[]]$sonnet, [Predicate[int]]{ param($n) $n -gt 64000 })
  $later = @($sonnet | Select-Object -Skip ($first + 1) | Where-Object { $_ -gt 64000 })
  Check 'the cap is learned once, then every Sonnet call stays under it' ($first -ge 0 -and $sonnet[$first + 1] -eq 64000 -and $later.Count -eq 0) ($sonnet -join ',')

  Write-Output '--- quota'
  $q = Quota
  $cred = @($q.windows | Where-Object { $_.name -eq 'Credits' })[0]
  $month = @($q.windows | Where-Object { $_.name -eq 'This month via magpie' })[0]
  Check 'the balance goes down by what was spent' ($cred.balance -eq (5000 - $month.amount) -and $month.amount -gt 0) ($q.windows | ConvertTo-Json -Compress)
  Check 'calls include the octet-stream response' ($month.display -match '\b7 calls') $month.display

  Write-Output '--- unrelated refusals keep the account and balance'
  $balanceBefore = $cred.balance
  Mock '/_mode' @{ mode = 'plan' } | Out-Null
  $r = Chat 'gumloop/claude-opus-5-5'
  Check 'a plan refusal keeps its 403 status' ($r.status -eq 403) "$($r.status) $($r.body)"
  $list = & $magpie plugin 2>&1 | Out-String
  Check 'a plan refusal does not expire the sign-in' ($list -match 'signed in as mock@example.com') $list
  Mock '/_mode' @{ mode = 'upstream-credits' } | Out-Null
  $r = Chat 'gumloop/claude-sonnet-5-5'
  Check 'upstream provider credits keep the original 400' ($r.status -eq 400) "$($r.status) $($r.body)"
  $q = Quota
  $cred = @($q.windows | Where-Object { $_.name -eq 'Credits' })[0]
  Check 'unrelated refusals do not zero the balance' ($cred.balance -eq $balanceBefore -and $cred.balance -gt 0) ($q | ConvertTo-Json -Depth 5 -Compress)

  Write-Output '--- out of credits'
  Mock '/_mode' @{ mode = 'credits' } | Out-Null
  $r = Chat 'gumloop/claude-sonnet-5-5'
  Check 'out of credits is a 429' ($r.status -eq 429) "$($r.status) $($r.body)"
  $q = Quota
  $cred = @($q.windows | Where-Object { $_.name -eq 'Credits' })[0]
  Check 'quota shows none left' ($cred.remaining -eq 0 -or $cred.balance -eq 0) ($q | ConvertTo-Json -Depth 5 -Compress)

  Write-Output '--- refused key'
  Mock '/_mode' @{ mode = 'badkey' } | Out-Null
  $r = Chat 'gumloop/claude-sonnet-5-5'
  Check 'a refused key fails the request' ($r.status -ge 400) "$($r.status) $($r.body)"
  $q = Quota
  Check 'quota says to sign in again' ("$($q.error)" -match 'sign in again') ($q | ConvertTo-Json -Depth 5 -Compress)
  $list = & $magpie plugin 2>&1 | Out-String
  Write-Output "  (plugin list now: $(($list -split "`n" | Select-String 'gumloop \(').Line.Trim()))"
  Mock '/_mode' @{ mode = 'ok' } | Out-Null
} finally {
  if ($serve -and -not $serve.HasExited) { Stop-Process -Id $serve.Id -Force }
  if (-not $mockProc.HasExited) { Stop-Process -Id $mockProc.Id -Force }
}
Write-Output ''
if ($script:failed) { Write-Output "$script:failed check(s) failed"; exit 1 } else { Write-Output 'all checks passed' }
