# Runs magpie in a sandbox HOME (G:\gumloop_magpie\.sandbox), so your own
# magpie, agents and sign-ins are left alone. Any arguments go to magpie.
#
#   .\try.ps1                                  add the plugin (again) and list it
#   .\try.ps1 plugin login gumloop             sign in: API key, user id, email, credits left
#   .\try.ps1 provider test gumloop            one tiny request per model API
#   .\try.ps1 provider test gumloop gpt-6-sol  or just one model
#   .\try.ps1 quota                            the usage hook (credit estimate)
#   .\try.ps1 plugin logout gumloop
param([Parameter(ValueFromRemainingArguments = $true)] [string[]] $MagpieArgs)

$root = $PSScriptRoot
$sb = Join-Path $root '.sandbox'
New-Item -ItemType Directory -Force $sb | Out-Null
$env:HOME = $sb
$env:USERPROFILE = $sb
$env:XDG_CONFIG_HOME = Join-Path $sb '.config'
$env:XDG_CACHE_HOME = Join-Path $sb '.cache'
$env:MAGPIE_ADDR = '127.0.0.1:3499'

if (-not $MagpieArgs -or $MagpieArgs.Count -eq 0) {
    magpie plugin add (Join-Path $root 'packages\gumloop')
    magpie plugin
} else {
    magpie @MagpieArgs
}
exit $LASTEXITCODE
