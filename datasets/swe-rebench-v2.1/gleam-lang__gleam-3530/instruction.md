Deprecate `..` discard if not preceded by a comma
I found a piece of syntax we should deprecate like we did with the list discard
```gleam
Wibble(one: name ..)
// Is valid and interpreted as
Wibble(one: name, ..)

// and
Wibble(one: ..)
// Is valid and interpreted as
Wibble(one:, ..)
```
