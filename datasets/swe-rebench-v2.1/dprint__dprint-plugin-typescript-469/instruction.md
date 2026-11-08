Incorrect output for inline block statement containing an empty statement
**Describe the bug**

dprint-plugin-typescript version: 0.80.2

**Input Code**

An if statement with a block statement that only contains an empty statement, all in one line (see [Playground](https://dprint.dev/playground/#code/JYMwBAFALgTgrgUwJRgN4G4C+Q/language/typescript)):

```ts
if (true) {;}
```

**Expected Output**

dprint should remove the empty statement, but keep the block statement:

```ts
if (true) {}
```

**Actual Output**

dprint currently removes the block statement entirely:

```ts
if (true)
```

---

Note that dprint formats this code correctly when the block statement is not on a single line (see [Playground](https://dprint.dev/playground/#code/JYMwBAFALgTgrgUwJRgN4CgxbAbnQXyA/language/typescript)):

```ts
// Before
if (true) {
    ;
}

// After
if (true) {
}
```

### Additional contract requirements

- For `if (true) {;;}` and `while (true) {;;}`, format the empty blocks on multiple lines:

```ts
if (true) {
}
while (true) {
}
```

- For `while (true) {;}`, format as `while (true) {}` (the same one-empty-statement
  behaviour as the `if` case above).
