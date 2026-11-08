Compiler crash when compiling specific pattern on javascript
For some reason, when compiling a bit array pattern inside a tuple pattern on the javascript target, the compiler will crash. For example, this code:
```gleam
pub fn main() {
  let assert #(<<>>) = todo
}
```
Causes a panic in the code generation module for patterns on JavaScript. This code compiles and runs fine on Erlang.
Discord thread where this was discussed: https://discord.com/channels/768594524158427167/1377007726017642719
