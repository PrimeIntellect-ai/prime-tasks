Issues when using intersection and types with fallback
## 🐛 Bug report

### Current Behavior

```typescript
import * as t from 'io-ts';
import { withFallback} from 'io-ts-types';

const MyType = t.intersection([
  withFallback(t.type({ prop1: t.string }), { prop1: 'a' }),
  withFallback(t.type({ prop2: t.number }), { prop2: 1 }),
]);

MyType.decode(undefined); // throws: TypeError: Cannot read property 'prop1' of undefined
```

### Expected behavior

As both of the subtypes will return a value when decoding `undefined`, the intersection should also succeed (or fail without exception).

`MyType.decode(undefined)` to be equal to `right({ prop1: 'a', prop2: 1 })`

### Suggested solution(s)

[HIDDEN]
