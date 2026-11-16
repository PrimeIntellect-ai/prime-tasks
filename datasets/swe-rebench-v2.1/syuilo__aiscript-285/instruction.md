Whitespace should be required between "let" and the variable name in the each/for statements
The grammar for the for loop is written like this:

[HIDDEN]

([source](https://github.com/syuilo/aiscript/blob/8ab9c279009fe8453c9a65cf3bb7b359d081bb56/src/parser/parser.peggy#L234C4-L234C38))

Which means that I could write something like this and it would still be valid:
```
for (leti = 1,10) {
    <: i
}
```

I'm assuming this is unintended behavior, since the VarDef statement clearly requires a space between `let` and the variable name.

Edit: The `each` statement also exhibits the same behavior.
