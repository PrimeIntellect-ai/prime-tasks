Wrong code generated for while statement, edgecase
**Describe the bug**

The falsy while statement should not remove variable declarations.

**To Reproduce**

Minimal code to reproduce the bug

```js
function a() {
  ++i;
  while (false) {
    var i = meow();
  }
}
```

**Actual Output**

If there is no Error thrown,

```js
function a(){
  ++i;
}
```

**Expected Output**

```js
function a(){
  ++i;
  var i;
}
```

**Configuration**

How are you using babel-minify?

`babel-minify CLI`

babel-minify version: `0.5.0`

babel version : `7.0.0-beta.49`

babel-minify-config: default

**Possible solution**

[HIDDEN]

### Additional contract requirements

- When a falsy `while` statement is eliminated, preserve variable declarations from its body while removing the unreachable loop and its initializer.
