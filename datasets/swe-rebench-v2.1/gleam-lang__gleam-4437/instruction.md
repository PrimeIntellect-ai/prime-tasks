"Extract constant" code action extracts functions
With this code:
```gleam
pub fn main() {
  io.println("Hello, world")
  // ^ trigger code action
}
```
The LSP offers an "Extract Constant" code action to perform the following transformation:
```gleam
const nil = io.println("Hello, world")

pub fn main() {
  nil
}
```
Which is invalid code, functions cannot appear in constants
