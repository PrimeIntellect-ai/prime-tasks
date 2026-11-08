Incorrect parsing of nested tuple access
<!--
Please include the following:
- Steps and code to reproduce the problem
- Versions for Gleam, OS, the runtime and any other software used
- Logs from running Gleam with the `GLEAM_LOG` environment variable set to `trace`
-->
As discussed in discord, there is likely a parser bug that is causing nested tuple access to result in odd compilation errors, as well as the formatter putting the access (`0.0` in the below example) on a new line.


With the following[ gleam code](https://playground.gleam.run/#N4IgbgpgTgzglgewHYgFwEYA0IDGyAuES+aIAZkgAT4CuADjAPpzEAUAlJQLQB8lAxK0EBJYu0wDWo/O07AAOlUmD04wQCZZigL6LFdGgCNKFSgFsAhiw69K0ygqW0GzNuwB0ABi869KbUA=):
```gleam
fn tups_int() -> #(#(Int), #(Int)) {
  #(#(1),#(2))
}
pub fn main() -> Int {
  tups_int().0.0
}
```
The compiler is reporting this error:

```
error: Unknown record field
   ┌─ /src/main.gleam:13:13
   │
13 │   tups_int().0.0
   │             ^ This field does not exist

The value being accessed has this type:

    #(#(Int), #(Int))

It does not have any fields.

error: Type mismatch
   ┌─ /src/main.gleam:13:14
   │
13 │   tups_int().0.0
   │              ^^^

The type of this returned value doesn't match the return type
annotation of this function.

Expected type:

    Int

Found type:

    Float
 ```
