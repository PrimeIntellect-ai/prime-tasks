spaceBeforeBrace flags trailing whitespace before a newline
**Which version of `lesshint` are you using?**
4.1.1

**How are you running `lesshint`? CLI, Node.js API, Grunt/Gulp plugin?**
CLI and Node.js API

**What's your `.lesshintrc` configuration?**
*(everything else is disabled)*
```js
"spaceBeforeBrace": {
    "enabled": true,
    "style": "new_line"
},
"trailingWhitespace": true,
```

**If you're reporting a bug, please show us some code that's failing.**
*Note the space after `.bbb`
```less
.bbb
{}
```

**What did you expect to happen?**

```
Warning: original.less: line 2, col 5, trailingWhitespace: There shouldn't be any trailing whitespace.
```

**What's the actual result?**

```
Warning: original.less: line 2, col 5, trailingWhitespace: There shouldn't be any trailing whitespace.
Warning: original.less: line 3, col 1, spaceBeforeBrace: Opening curly brace should be on its own line.
```

**Would you be interested in submitting a PR for this issue?**

I'll take a look. [HIDDEN]

None of the test cases in `test/specs/linters/space_before_brace.js` refer to equivalents of `.bar \n{}`, just `.bar\n {}`.

### Additional contract requirements

- With `spaceBeforeBrace` set to `new_line`, spaces or tabs immediately before a single newline between a selector and its opening brace, and spaces or tabs indenting the brace after that newline, must not cause a `spaceBeforeBrace` warning. This does not suppress an independent `trailingWhitespace` warning.
