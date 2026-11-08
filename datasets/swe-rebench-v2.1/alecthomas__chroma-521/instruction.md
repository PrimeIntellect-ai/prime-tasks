New SCSS module system not highlighting correctly
SCSS language has introduced many new features recently. The new module system `@use` doesn't highlight `with` configs correctly.

For example, the following example renders correctly using prism.js:

![image](https://user-images.githubusercontent.com/9663168/108617697-840c4100-73e6-11eb-8a9e-ab71ab602fcd.png)

However, in chroma the key/value pairs are being recognized as `chroma .nt` and are not able to be colored separately:

![image](https://user-images.githubusercontent.com/9663168/108617730-a9994a80-73e6-11eb-8f72-74e59186bfd8.png)

Also the `$` symbol in front of the word config is being recognized by chroma as an error `.chroma .err`

### Additional contract requirements

The `@use`/`@forward` `with (...)` configuration body must be tokenised so that configuration keys and their values are highlighted with distinct token classes. For the configuration body the following token classes are required:

- `@use` and `with` are `Keyword`.
- The module string (for example `'library'`) is `LiteralStringSingle`.
- Configuration variable names such as `$black` and `$config` are `NameVariable`; the leading `$` must never be tokenised as `Error`.
- Configuration keys (for example `important`, `utility`, `leading-trim`, `properties`, `variants`, `both`) are `NameAttribute`.
- The boolean value `true` is `NamePseudo`.
- The value `both` is `NameEntity`.
- A bare identifier used as a value (for example `trim`, or `leading-trim` inside `(leading-trim)`) is `Name`.
- `:` and `,` are `Operator`; parentheses and semicolons are `Punctuation`; hex colours such as `#222` are `LiteralNumberHex`; whitespace is `Text`.
