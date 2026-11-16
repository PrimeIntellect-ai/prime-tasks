LSP: Goto Definition not working properly for unqualified imports
<!--
Please include the following:
- Steps and code to reproduce the problem
- Versions for Gleam, OS, the runtime and any other software used
- Logs from running Gleam with the `GLEAM_LOG` environment variable set to `trace`
-->

The LSP action "Goto Definition" (`gd` in nvim) is not working for unqualified imported functions.
With the following example of (part of) a file (from the [Building your first Gleam web app with Wisp and Lustre](https://gleaming.dev/articles/building-your-first-gleam-web-app/) tutorial),

```gleam
import app/routes/item_routes.{items_middleware}
import app/web.{type Context}
import wisp.{type Request, type Response}

pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- web.middleware(req, ctx)
  use ctx <- items_middleware(req, ctx)
// ...
```

the following behaviors are observed:
* Placing the cursor on `items_middleware` and hitting `gd` moves the cursor to the `req` symbol on the same line.
* Placing the cursor on `web.middleware` (specifically on the `.middleware` part) and hitting `gd` correctly jumps to that function's definition in `app/web`.
* Placing the cursor on any of the imported types (`Context` or `Request`) and hitting `gd` correctly jumps to their definition.

Gleam v1.3.2 running on WSL (Ubuntu 22.04.4 LTS)
Neovim v0.11.0-dev
