StateReaderTaskEither.traverseArray drops state updates between iterations
## 🐛 Bug report

### Current Behavior

In fp-ts 2.10.2, SRTE.traverseArray does not pass the output state from each step to the subsequent step. Each step receives the initial state. As a result, all state transformations are lost except for the final one.

### Expected behavior

In fp-ts 2.9.5, SRTE.traverseArray passes the output state from each step to the subsequent step. This is the expected behavior.

### Reproducible example

```typescript
import * as E from "fp-ts/Either";
import * as SRTE from "fp-ts/StateReaderTaskEither";
import { pipe } from "fp-ts/function";

async function main(): Promise<void> {
  const state = pipe(
    await pipe([1, 2, 3], SRTE.traverseArray(fn))([])({})(),
    E.map(([_, state]) => state),
    E.getOrElseW(() => null)
  );

  console.log(state);
}

function fn(
  v: number
): SRTE.StateReaderTaskEither<ReadonlyArray<number>, {}, Error, void> {
  return SRTE.modify((a) => [...a, v]);
}

main();
```

2.9.5 prints:

```[ 1, 2, 3 ]```

2.10.2 prints:

```[ 3 ]```


| Software   | Version(s) |
| ---------- | ---------- |
| fp-ts          | 2.10.2           |
| TypeScript |   4.2.4         |
