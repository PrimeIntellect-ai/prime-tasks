arrowFunction.useParentheses=preferNone removes parens around jsdoc comment for single parameter
**Describe the bug**

dprint-plugin-typescript version: 0.71.2

Without the parens, the jsdoc comment doesn't apply to the parameter anymore.

**Input Code**

```ts
process.on("unhandledRejection", (/** @type {any}*/ err) => {
    if (err) {
        console.error(err.stack || err.message);
    }
    process.exit(1);
});
```

**Expected Output**

```ts
process.on("unhandledRejection", (/** @type {any}*/ err) => {
    if (err) {
        console.error(err.stack || err.message);
    }
    process.exit(1);
});
```

**Actual Output**

```ts
process.on("unhandledRejection", /** @type {any}*/ err => {
    if (err) {
        console.error(err.stack || err.message);
    }
    process.exit(1);
});
```
