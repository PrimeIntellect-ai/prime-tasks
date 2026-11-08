Comment above case gets extra newline
**Describe the bug**

dprint-plugin-typescript version: 0.71.2

Comments in the middle of cases get an extra newline before them.

**Input Code**

```ts
switch (foo) {
    // Types
    case SyntaxKind.A:
        return 1234;

    // Values
    case SyntaxKind.B:
        return 1234;
}
```

**Expected Output**

```ts
switch (foo) {
  // Types
  case SyntaxKind.A:
    return 1234;

  // Values
  case SyntaxKind.B:
    return 1234;
}
```

**Actual Output**

```ts
switch (foo) {
  // Types
  case SyntaxKind.A:
    return 1234;

  // Values

  case SyntaxKind.B:
    return 1234;
}
```
