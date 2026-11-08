no-angle-bracket-type-assertion fails when typeAnnotation is not a reference type.
the following code throws an exception when no-angle-bracket-type-assertion is enabled

```ts
const a : number = <number>5;
```

but it works with reference types

```ts
interface A {}
const a : A = <A>{};
```

Already have a PR for this
