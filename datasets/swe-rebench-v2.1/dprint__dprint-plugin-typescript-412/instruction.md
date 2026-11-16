Comment block before case has lines after the first unindented
**Describe the bug**

dprint-plugin-typescript version: 0.71.2

**Input Code**

```ts
switch (x) {
    case SyntaxKind.A:
        if (condition) {
            return 1234;
        }
        // Something something something
        // Something else
        // falls-through

    case SyntaxKind.B:
        return "cool"
}
```

**Expected Output**

```ts
switch (x) {
    case SyntaxKind.A:
        if (condition) {
            return 1234;
        }
        // Something something something
        // Something else
        // falls-through

    case SyntaxKind.B:
        return "cool";
}
```

Also, the newline above is deleted after the comment (not sure if this is the same bug).

**Actual Output**

```ts
switch (x) {
    case SyntaxKind.A:
        if (condition) {
            return 1234;
        }
        // Something something something
    // Something else
    // falls-through
    case SyntaxKind.B:
        return "cool";
}
```
