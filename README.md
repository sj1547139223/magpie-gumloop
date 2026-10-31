# magpie-gumloop

A [magpie](https://usemagpie.ai) provider plugin for [Gumloop](https://www.gumloop.com): sign in with your Gumloop API key and user id, and use Gumloop's models from any agent magpie serves, with a local credit estimate (Gumloop's API has no balance endpoint).

The plugin is in [`packages/gumloop`](packages/gumloop); its README covers sign-in, models, the credit estimate and options. The layout follows [magpie-community/plugins](https://github.com/magpie-community/plugins), where it is meant to go once it has been tested on a real account.

## Use it

```sh
magpie plugin add <path to this repo>/packages/gumloop
magpie plugin login gumloop
magpie provider test gumloop
magpie quota
```

## Test it

```powershell
cd packages/gumloop; bun test          # unit tests
.\test\e2e.ps1                         # real magpie against a mock Gumloop, in a throwaway sandbox
.\try.ps1 plugin login gumloop         # a sandboxed magpie for trying a real account
```

`test/e2e.ps1` needs `magpie` and `node` on PATH. `try.ps1` and `test/e2e.ps1` keep their own HOME under `.sandbox*/`, so your own magpie and sign-ins are not touched.

## Status

Tested against a mock of Gumloop's API. The endpoints, headers and billing rules come from [vwfactory-dsh](https://github.com/cjj66619/vwfactory-dsh) and are not yet confirmed on a real account.

MIT. Not affiliated with Gumloop.
