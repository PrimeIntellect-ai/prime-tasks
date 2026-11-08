Semicolon removed after index signature on class declaration
**Describe the bug**

dprint-plugin-typescript version: 0.73.0

**Input Code**

```ts
declare class Foo {
    [key: string]: any;
}
```

**Expected Output**

```ts
declare class Foo {
    [key: string]: any;
}
```

**Actual Output**

```ts
declare class Foo {
    [key: string]: any
}
```
