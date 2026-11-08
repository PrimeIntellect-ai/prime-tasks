no-var fix isn't safe in the global scope
I'm not sure what the project's policy is about safety of fixes, but the `no-var` can produce unsafe transformations when the var is global which makes it unsuitable for fixing arbitrary files.

This is a minimal example that isn't safe (and here's a [demo page link to it](https://eslint.org/demo/#eyJ0ZXh0IjoiXG52YXIgeCA9IDEiLCJvcHRpb25zIjp7InBhcnNlck9wdGlvbnMiOnsiZWNtYVZlcnNpb24iOjgsInNvdXJjZVR5cGUiOiJzY3JpcHQiLCJlY21hRmVhdHVyZXMiOnt9fSwicnVsZXMiOnsibm8tdmFyIjoyfSwiZW52Ijp7ImJyb3dzZXIiOnRydWV9fX0=)):

```js
var x = 10;
```

When fixed by `eslint` it produces:

```js
let x = 10;
```

However this isn't equivalent as in the global context `let`/`const` statements have different semantics than `var`, take this code for instance:

```html
<script>
    var x = 10;
</script>
<script>
    var x = 20;
</script>
<script>
    console.log(x);
    console.log(window.x);
</script>
```

Running that code will print 20 twice, but in contrast if we run the `eslint` "fixed" version:

```html
<script>
    let x = 10;
</script>
<script>
    let x = 20;
</script>
<script>
    console.log(x);
    console.log(window.x);
</script>
```

In this case it will print `10` followed by `undefined`, in addition the second script will simply throw an error that `x` is already defined.

Now I'm not planning on using globals in this way in new code, but a lot of files in the code base are many years old and I know I've seen `var someGlobalName` being used to add things as `window.someGlobalName` so running the `no-var` on the code base is very likely to break things. It would be nice at least to have an option to `no-var` like `ignore-global` or something like that to prevent breaking of such code.

### Additional contract requirements

- The rule still reports `Unexpected var, use let or const instead.` for every `var` declaration; only the automatic fix is skipped for global-scope variables.
- A `var` declaration in a script's global scope is a global variable: it is reported but not automatically fixed. This includes declarations nested inside top-level blocks.
- When the program has a special top-level scope - `sourceType: "module"` or `parserOptions.ecmaFeatures.globalReturn: true` - top-level `var` declarations are not global and are still fixed (for example `var foo = 1;` becomes `let foo = 1;`).
