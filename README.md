# magpie-gumloop

A [magpie](https://usemagpie.ai) provider plugin for [Gumloop](https://www.gumloop.com): sign in with your Gumloop API key and user id, and use Gumloop's models from any agent magpie serves, with a local credit estimate (Gumloop's API has no balance endpoint).

The plugin is in [`packages/gumloop`](packages/gumloop); its README covers sign-in, models, the credit estimate and options. The layout follows [magpie-community/plugins](https://github.com/magpie-community/plugins).

## Use it

```sh
magpie plugin add <path to this repo>/packages/gumloop
magpie plugin login gumloop
magpie provider test gumloop
magpie quota
```

## Test it

```powershell
bun test ./packages/gumloop           # unit tests, from the repository root
.\test\e2e.ps1                         # real magpie against a mock Gumloop, in a throwaway sandbox
.\try.ps1 plugin login gumloop         # a sandboxed magpie for trying a real account
```

`test/e2e.ps1` needs `magpie` and `node` on PATH. `try.ps1` and `test/e2e.ps1` keep their own HOME under `.sandbox*/`, so your own magpie and sign-ins are not touched.

## Status

Tested with a real Gumloop account and magpie's gateway, including sign-in,
streaming, tool calls and the local credit ledger, plus a mock API regression
suite. API integration and the original billing estimates build on
[vwfactory-dsh](https://github.com/cjj66619/vwfactory-dsh). Credits remain an
estimate; real requests do not verify the account's invoice or remaining balance.

MiniMax M3 is temporarily omitted because Gumloop's upstream route rejects its
own forwarding parameters. See the package README for this limitation and the
catalog-to-chat model mappings.

MIT. Not affiliated with Gumloop.
