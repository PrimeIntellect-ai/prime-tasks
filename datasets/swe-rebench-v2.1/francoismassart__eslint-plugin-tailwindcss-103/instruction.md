[BUG] `no-custom-classname` false negative on arrays/objects passed to callee
**Describe the bug**
`classnames` and similar allow:
- objects where the keys are classes and values are boolean representing whether the class is enabled
- arbitrarily nested arrays to group classes organizationally or with conditionals

For example:
```js
classnames(
  ["asdf foo"],
  myFlag && [
    "bar",
    someBoolean ? ["baz"] : { "qwerty": someOtherFlag },
  ]
);
```

`no-custom-classname` does not identify invalid classes within arrays and objects passed to a callee.

**To Reproduce**
Steps to reproduce the behavior:
1. Ensure `classnames` is configured as a callee
2. Paste the above code block

**Expected behavior**
All five classes (`asdf`, `foo`, `bar`, `baz`, `qwerty`) are identified as invalid

**Environment (please complete the following information):**
 - OS: macOS
 - Softwares + version used:
     - node 16.3.0
     - yarn 1.22.10
     - eslint 7.32.0
     - eslint-plugin-tailwindcss 3.2.0
     - tailwindcss v3.0.15

**Additional context**
I'd be happy to make a PR if this change makes sense.
