[v6.1.0] Fails if you have two required modules
> Sorry I'm a little late to the game, but if you have two required modules:
>
> ```
> node-dev -r dotenv-safe/config -r ts-node/register/transpile-only
> ```
>
> Then it fails with
> ```
> Error: Cannot find module 'dotenv-safe/config,ts-node/register/transpile-only'
> ```
>
> I suspect it is a consequence of this "wrangling"


_Originally posted by @jraoult in https://github.com/fgnass/node-dev/pull/237#issuecomment-709146208_
