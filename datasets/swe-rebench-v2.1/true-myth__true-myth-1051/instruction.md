`Task` incorrectly implements `PromiseLike` interface
Code:

```typescript
import { Task } from 'true-myth'

export const foo: PromiseLike<unknown> = Task.resolve(123)
```

Error:

```plaintext
Type 'Task<number, never>' is not assignable to type 'PromiseLike<unknown>'.
  Type 'Pending<number, never>' is not assignable to type 'PromiseLike<unknown>'.
    Types of property 'then' are incompatible.
      Type '<A, B>(onSuccess?: ((result: Result<number, never>) => A | PromiseLike<A>) | undefined, onRejected?: ((reason: unknown) => B | PromiseLike<B>) | undefined) => PromiseLike<...>' is not assignable to type '<TResult1 = unknown, TResult2 = never>(onfulfilled?: ((value: unknown) => TResult1 | PromiseLike<TResult1>) | null | undefined, onrejected?: ((reason: any) => TResult2 | PromiseLike<TResult2>) | null | undefined) => PromiseLike<...>'.
        Types of parameters 'onSuccess' and 'onfulfilled' are incompatible.
          Type '((value: unknown) => TResult1 | PromiseLike<TResult1>) | null | undefined' is not assignable to type '((result: Result<number, never>) => TResult1 | PromiseLike<TResult1>) | undefined'.
            Type 'null' is not assignable to type '((result: Result<number, never>) => TResult1 | PromiseLike<TResult1>) | undefined'.(2322)
```

Playground link: https://www.typescriptlang.org/play/?#code/JYWwDg9gTgLgBAbzgFQIYGcDWcC+cBmUEIcA5DFAK4CmAtCAJ4wAWpAUG9QB6SxwDGEAHbp4+CBABccAApEQwdNQAywTNQA8lIZiEQA7kIB8cALwoMmAHRRq6CABsAbtQAUARgBMAZgCUQA
