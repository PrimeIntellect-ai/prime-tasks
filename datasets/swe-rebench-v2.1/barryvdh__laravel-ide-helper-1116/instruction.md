Macro docblock regression: empty docblock
### Versions:
- ide-helper Version: 2.8.1
- Laravel Version: 8.15.x <!-- remove if not applicable -->
- PHP Version: 7.4.x

### Description:

The #1006 added support for macros but it contains regression:

![image](https://user-images.githubusercontent.com/1329824/100515455-cc281880-3195-11eb-9552-5590519e8c27.png)

The problem is `Closure`s also can have docblock and in the previous version it parsed and saved correctly. After  #1006 ide-helper always loses it :(

My suggestion is: if docblock present ide-helper should use it (`[HIDDEN]`); if not - add it.

@domkrm

### Additional contract requirements

- When a macro closure has a docblock, the generated macro docblock must preserve the original comment text.
- Generate `@param` tags only when the original docblock contains no `@param` tag. Generate one tag per closure parameter, using its declared type; write a nullable type as `<type>|null`, and use `mixed` when a parameter has no declared type. For a nullable `int` parameter named `$a`, the generated tag is exactly `@param int|null $a`.
- Generate an `@return` tag only when the closure declares a return type and the original docblock contains no `@return` tag. For an `int` return type, the generated tag is exactly `@return int`.
- A `@see` tag is always present in the generated macro docblock.
- Do not generate a `@return` tag when the closure has no declared return type and its original docblock contains no `@return` tag.
- When the closure has no docblock, the generated macro docblock's text must be empty.
