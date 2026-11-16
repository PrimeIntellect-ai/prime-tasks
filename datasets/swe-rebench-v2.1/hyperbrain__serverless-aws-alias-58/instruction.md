Complete stage removal not possible
When the alias plugin is used and only the master alias is left, `serverless remove` will error out, and `serverless alias remove` does not remove the master alias.

The alias plugin should support removing the master alias including the whole service stack.
Removal should only be possible if there are no other aliases deployed.

See thread https://github.com/serverless/serverless/issues/3805

### Additional contract requirements

- `removeAlias` returns a Promise. When an invalid master-alias removal scenario is detected, the error is signalled either by throwing synchronously or by rejecting the returned Promise, with a `Serverless.Error`.
- When the master alias is targeted for removal while other aliases are still deployed, the error message contains the names of the remaining aliases (for example `myAlias`).
- When the master alias is targeted for removal but the master alias stack is not deployed, the error message contains the text `Internal error`.
