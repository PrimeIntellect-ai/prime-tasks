dprint removes type arguments in `typeof` expressions
dprint removes type arguments to the target of `typeof` expressions, changing the meaning of the code.

dprint 0.31.1
dprint-plugin-typescript version: 0.73.1

**Input Code**

```ts
function getCtor(): typeof MyClass<Foo>;
```

**Expected Output**

```ts
function getCtor(): typeof MyClass<Foo>;
```

**Actual Output**

```ts
function getCtor(): typeof MyClass;
```
