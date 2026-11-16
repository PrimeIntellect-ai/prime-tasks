Do not show errors for wrong labels if the called function/variant constructor doesn't exist
When calling a function (or variant constructor) that doesn't exists like this:
```gleam
pub fn main() {
  wibble(wobble: "hello, Joe!")
  // or Wibble(wobble: "Hello, Joe!")
}
```
The compiler complains about the function not existing:
```text
error: Unknown variable
  ┌─ /src/main.gleam:4:3
  │
4 │   Wibble(wobble: "Hello, Joe!")
  │   ^^^^^^

The custom type variant constructor `Wibble` is not in scope here.
```
But it also shows an error for each of the used labels:
```text
error: Unexpected labelled argument
  ┌─ /src/main.gleam:4:10
  │
4 │   Wibble(wobble: "Hello, Joe!")
  │          ^^^^^^^^^^^^^^^^^^^^^

This argument has been given a label but the constructor does
not expect any. Please remove the label `wobble`.
```
I think it doesn't make a lot of sense to show this error when the function itself doesn't exist and I'd like to remove it. What do you think?
