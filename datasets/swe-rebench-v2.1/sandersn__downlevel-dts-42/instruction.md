Incorrect downlevelling of `export * as foo from 'bar'`
### Input code:

```ts
export * as TSESTree from './ts-estree';
```

### Expected output:

```ts
import * as TSESTree from './ts-estree';
export { TSESTree };
```

### Actual output:

```ts
import * as TSESTree_1 from './ts-estree';
export { TSESTree_1 as TSESTree } from './ts-estree';
```


See also

Test input:

https://github.com/sandersn/downlevel-dts/blob/ca924f6fdb2abc875b6884dea541327c57fe443d/test/test.d.ts#L27-L28

Incorrect test output:

https://github.com/sandersn/downlevel-dts/blob/ca924f6fdb2abc875b6884dea541327c57fe443d/baselines/ts3.4/test.d.ts#L24-L26
