Unstable formatting on oddly-spaced block comment
**Describe the bug**

dprint-plugin-typescript version: 0.84.0

**Input Code**

```ts
/* * * * * * * * * * *
 *  Native Promises  *
 * * * * * * * * * * */
```

**Expected Output**

Not sure 😄

**Actual Output**

```
Message: Formatting not stable. Bailed after 5 tries. This indicates a bug in the plugin where it formats the file differently each time.
```

### Additional contract requirements

- Formatting the reported comment must complete stably rather than fail with an unstable-formatting error, and must reproduce the comment unchanged.
- For the given multiline block comment, formatting must produce exactly this output:

```ts
/* * * * * * * * * * *
 *  Some Text Here1  *
 * * * * * * * * * * */
const test = 5;
```
