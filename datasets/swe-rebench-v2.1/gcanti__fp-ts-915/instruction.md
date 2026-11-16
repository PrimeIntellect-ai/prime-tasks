Array to model non-determinism
## 🐛 Bug report

I have been using `Array` in combination with `liftA2` to model some non-determinism / cartesian product-like calculations. I did this under the assumption that `Array` would behave similar to `List` in Haskell. Maybe this assumption is wrong tough?

With fp-ts 2 removing the `liftN` functions and recommending `sequenceS` and `sequenceT` instead, I decided to have a go at refactoring my implementation using `sequenceS`. But to my surprise this didn’t result in the same behavior.

I can probably work around it for now by using `comprehension` instead. Though I would still like to know if this is the expected behavior for `Array`.

I have done some tests to reproduce this with both 1.19.4 and 2.0.2

### Current Behavior

1.19.4
```
liftA2 [
  '1 - a', '1 - b',
  '1 - c', '2 - a',
  '2 - b', '2 - c',
  '3 - a', '3 - b',
  '3 - c'
]
sequenceS [
  '1 - c', '1 - c',
  '1 - c', '2 - c',
  '2 - c', '2 - c',
  '3 - c', '3 - c',
  '3 - c'
]
sequenceT [
  '1 - a', '1 - b',
  '1 - c', '2 - a',
  '2 - b', '2 - c',
  '3 - a', '3 - b',
  '3 - c'
]
```

2.0.2
```
sequenceS [
  '1 - c', '1 - c',
  '1 - c', '2 - c',
  '2 - c', '2 - c',
  '3 - c', '3 - c',
  '3 - c'
]
sequenceT [
  '1 - a', '1 - a',
  '1 - a', '2 - a',
  '2 - a', '2 - a',
  '3 - a', '3 - a',
  '3 - a'
]
```

### Expected behavior

I expected that all the variants should result in the same output as the `liftA2` variant.

It is also interesting that `sequenceT` behaves like `liftA2` in 1.19.4 but completely different in 2.0.2.

### Reproducible example

This is the code that produces the above output.

1.19.4
```typescript
import { liftA2, sequenceS, sequenceT } from "fp-ts/lib/Apply";
import { array, map } from "fp-ts/lib/Array";
import { curry } from "fp-ts/lib/function";
import { pipe } from "fp-ts/lib/pipeable";

function test(x: number, y: string): string {
  return `${x} - ${y}`;
}

const a1 = [1, 2, 3];
const a2 = ["a", "b", "c"];

const t1 = liftA2(array)(curry(test))(a1)(a2);
const t2 = pipe(
  sequenceS(array)({ x: a1, y: a2 }),
  map(({ x, y }) => test(x, y))
);
const t3 = pipe(
  sequenceT(array)(a1, a2),
  map(([x, y]) => test(x, y))
);

console.log("liftA2", t1);
console.log("sequenceS", t2);
console.log("sequenceT", t3);
```

2.0.2
```typescript
import { sequenceS, sequenceT } from "fp-ts/lib/Apply";
import { array, map } from "fp-ts/lib/Array";
import { pipe } from "fp-ts/lib/pipeable";

function test(x: number, y: string): string {
  return `${x} - ${y}`;
}

const a1 = [1, 2, 3];
const a2 = ["a", "b", "c"];

const t2 = pipe(
  sequenceS(array)({ x: a1, y: a2 }),
  map(({ x, y }) => test(x, y))
);
const t3 = pipe(
  sequenceT(array)(a1, a2),
  map(([x, y]) => test(x, y))
);

console.log("sequenceS", t2);
console.log("sequenceT", t3);
```

### Your environment

It mostly worked in 1.19.4 apart from `sequenceS` and not at all in 2.0.2

| Software   | Version(s) |
| ---------- | ---------- |
| fp-ts      |      1.19.4 & 2.0.2      |
| TypeScript |      3.5.3      |
