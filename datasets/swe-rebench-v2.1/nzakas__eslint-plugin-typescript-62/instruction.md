Type annotations not marked as used
Type annotations are not marked as used by typescript/no-unused-vars, so eslint:recommended/no-unused-vars marks this as an error.

```ts
// type literal declared elsewhere
import { Nullable } from '../types';

const str: Nullable<string> = 'hello';
console.log(str);
```

I know there is still a lot of work to do before we can say this rule is working as expected, but I think adding this won't hurt... current work is being tracked in the [typescript-eslint-parser repo](https://github.com/eslint/typescript-eslint-parser/issues/77).

### Additional contract requirements

A binding referenced by a TypeScript type annotation is considered used, including references in function parameter and return type annotations and names nested within a type expression. A type annotation must not cause unrelated bindings to be considered used.
