Target support not checked for unused unqualified imported values
Example:

```rust
import gleam/erlang.{rescue}
import gleam/io

pub fn main() {
    io.println("Hello, Joe!")
}
```

Generates an import in the JS module to `gleam/erlang.{rescue}`, even though this value is never used:

```bash
$ gleam run --target javascript
  ┌─ /home/arkan/Projects/probe/gleam/app/src/app.gleam:1:22
  │
1 │ import gleam/erlang.{rescue}
  │                      ^^^^^^ This imported value is never used

Hint: You can safely remove it.
   Compiled in 0.04s
    Running app.main
file:///home/arkan/Projects/probe/gleam/app/build/dev/javascript/app/app.mjs:2
import { rescue } from "../gleam_erlang/gleam/erlang.mjs";
         ^^^^^^
SyntaxError: The requested module '../gleam_erlang/gleam/erlang.mjs' does not provide an export named 'rescue'
    at ModuleJob._instantiate (node:internal/modules/esm/module_job:134:21)
    at async ModuleJob.run (node:internal/modules/esm/module_job:217:5)
    at async ModuleLoader.import (node:internal/modules/esm/loader:323:24)
    at async loadESM (node:internal/process/esm_loader:28:7)
    at async handleMainPromise (node:internal/modules/run_main:113:12)

Node.js v20.12.2

$ gleam -V
gleam 1.2.1
```

I noticed this in practice when trying to compile Wisp to Javascript. Wisp depends on Mist for `mist_handler`, which in turn imports `gleam/erlang.{rescue}` unqualified. I never called erlang-specific functions; instead I wanted to experiment whether or not you _could_ use Wisp as a framework for serverless functions, since its `Request -> Response` structure is really similar to what you are expected to expose from Javascript.

~joshi :purple_heart:
