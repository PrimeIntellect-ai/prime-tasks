Reference types directives appear to be duplicated
If an input d.ts has a reference directive like
```ts
/// <reference types="node" />
```

then that line will appear twice in the output d.ts:

```ts
/// <reference types="node" />
/// <reference types="node" />
```
