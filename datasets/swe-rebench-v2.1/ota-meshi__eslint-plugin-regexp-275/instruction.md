`regexp/negation` false positives because of `i` flag
See the following example:

```js
var re2 = /[^\P{Ll}]/iu;
```

![image](https://user-images.githubusercontent.com/20878432/124463287-f9bfea80-dd92-11eb-9e42-0c3524d89b30.png)

Ignoring the strange suggested fix (this will be a separate issue), the report is incorrect.

`/[^\P{Ll}]/iu` != `/\p{Ll}/iu`:
The Canonicalize operation of the `i` flag is applied _before_ the character class is inverted. This example, `\P{Ll}` means "all character that are not lower-case letters". Since`\p{Ll}` contains all upper-case letters, it will also contain all lower-case letters after the Canonicalize operation (not quite right but almost), so `\P{Ll}` matches (almost) all characters. The character class will then match (almost) no character because it is inverted. This is obviously very different from `/\p{Ll}/iu` which matches (almost) all letter characters.
