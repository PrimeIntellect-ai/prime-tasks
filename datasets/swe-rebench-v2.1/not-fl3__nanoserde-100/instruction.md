TomlParser doesn't allow keys with `0-9` in them
According to the [TOML spec](https://toml.io/en/v1.0.0#keys), this should be a valid TOML file
```toml
[thing]
1234 = "value"
```
If I parse it with nanoserde's TOML parser,
```rs
nanoserde::TomlParser::parse("[thing]\n1234 = \"value\"");
```
you get an error
```
Toml error: Unexpected token U64(1234) , line:2 col:1
```
Critically, a key with *any* `[0-9]` characters in it causes an error; `MyThing1 = "value"` leads to `Toml error: Unexpected token U64(1) , line:2 col:1`.
