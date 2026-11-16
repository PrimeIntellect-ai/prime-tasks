Can we have in `json_strip_comments()` additional functionallity that removes trailing commas?
See JSON5 capabilities from https://github.com/Joakker/lua-json5?tab=readme-ov-file#so-why-should-i-use-this-instead-of-the-builtin-json_decode:

> The advantage this package has over regular json, however, is that you get json5 features, such as comments, trailing commas and more flexible string literals.

So basically JSON5 added capabilities/syntax:
1.  comments
2. trailing commas
3. more flexible string literals (don't know what it means)

This package have a support for 1 via the function `json_strip_comments()`, but doesn't have a support for removing trailing commas, even though it seems that all the complex code is there, and [HIDDEN]
Not sure about 3, what it means and if we want it.

Basically, the nice function we could have is a transformer from JSON5 to JSON.

### Additional contract requirements

When `json_strip_comments()` processes JSON text, it should remove a comma that appears at the end of an object or array member list, even if whitespace separates the comma from the closing delimiter. Commas within JSON string values must remain unchanged.
