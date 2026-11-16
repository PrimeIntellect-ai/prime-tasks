Single line block with const variable has curlies removed
**Describe the bug**

dprint-plugin-typescript version: 0.84.0

**Input Code**

```ts
if (typeof err !== 'undefined') { const _err: Error = err; }
```

**Expected Output**

```ts
if (typeof err !== 'undefined') { const _err: Error = err; }
```

**Actual Output**

```ts
if (typeof err !== 'undefined') const _err: Error = err;
```

https://dprint.dev/playground/#code/JYMwBAFALgngDgUwPbgQJzWAhAXh2AcgFcA7AEwRGBITIIEowBvMAYyRIGcowB9dNAC4wAUQxJM+AQG4wAXyA/language/typescript

### Additional contract requirements

- Also preserve the braces when formatting these `if` and `while` statements:

```ts
if (true) { const _err = 5; }
while (true) { const _err = 5; }
if (true) { class Test {} }
while (true) { class Test {} }
```
