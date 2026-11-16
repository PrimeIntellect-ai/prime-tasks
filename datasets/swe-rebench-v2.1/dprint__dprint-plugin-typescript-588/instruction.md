Inappropriately removes type assertion in accessor definition
**Describe the bug**

dprint-plugin-typescript version: 0.88.5

`dprint fmt` removes the "definitely assigned" type assertion from properties marked with `accessor`, which results in TypeScript compilation errors, note the `!` in the definition of `includeSource`

**Input Code**

```ts
export class MarkedPlugin {
    @Option("includes")
    accessor includeSource!: string;
}
```

**Expected Output**
(no change)
```ts
export class MarkedPlugin {
    @Option("includes")
    accessor includeSource!: string;
}
```

**Actual Output**

```ts
export class MarkedPlugin {
    @Option("includes")
    accessor includeSource: string;
}
```
