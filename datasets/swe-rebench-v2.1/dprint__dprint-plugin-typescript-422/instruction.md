Space removed after method call on number literal
**Describe the bug**

dprint-plugin-typescript version: 0.73.1

**Input Code**

```ts
1+ 2 .toString() +3
```

**Expected Output**

```ts
1 + 2 .toString() + 3
```

or

```ts
1 + 2..toString() + 3
```

or

```ts
1 + (2).toString() + 3
```

**Actual Output**

```ts
1 + 2.toString() + 3;
```

Prettier adds parens; I think that's probably the best thing to do. See also: https://github.com/microsoft/TypeScript/issues/50686

### Additional contract requirements

- The formatter must produce these exact outputs for these inputs:

```ts
1+ 2 .toString() +3;    // 1 + (2).toString() + 3;
1+ 2_000 .toString() +3; // 1 + (2_000).toString() + 3;
1+ 2..toString() +3;    // 1 + 2..toString() + 3;
1+ 2.1.toString() +3;   // 1 + 2.1.toString() + 3;
1+ (2).toString() +3;   // 1 + (2).toString() + 3;
```
