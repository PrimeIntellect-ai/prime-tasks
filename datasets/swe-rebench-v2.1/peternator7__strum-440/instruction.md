Add the `suffix` attribute
This is similar to #296 , but instead of prefixing str infront, we add it behind:

```rs
use strum_macros::AsRefStr;

#[derive(AsRefStr)]
#[strum(prefix = "path/to/file/", suffix = ".asset")]
enum AssetTypes {
    Filename,
}

fn main() {
    println!("{}", AssetTypes::Filename.as_ref());  // prints "path/to/file/Filename.asset"
}
```

This could be useful for using `enum` types for specifying file paths, among many other things.

### Additional contract requirements

- The `suffix` attribute applies to the string produced by `Display` (i.e. `to_string()`) as well as to `AsRefStr::as_ref()`.
- The `suffix` attribute does not change how a value is parsed: `FromStr` and `TryFrom<&str>` still accept the variant's serialization names without requiring the suffix.
