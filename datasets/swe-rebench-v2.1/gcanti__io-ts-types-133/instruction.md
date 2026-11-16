Export all types from index
## 🚀 Feature request

I'd like to be able to import `io-ts-types` once and have all the codecs/combinators, like Ramda. AFAIK right now each thing must be imported from its own file.

### Current Behavior

```typescript
import { fromNullable } from 'io-ts-types/lib/fromNullable';
import { DateFromISOString } from 'io-ts-types/lib/DateFromISOString';
```

### Desired Behavior

```typescript
import { fromNullable, DateFromISOString } from 'io-ts-types/lib';
```

### Suggested Solution

[HIDDEN]

### Who does this impact? Who is this for?

All users except those who import individual files for bundle size reasons.

Bundle size is not a concern on NodeJS, where `io-ts` can be used for validation.

### Describe alternatives you've considered

It would be ideal to just `import 'io-ts-types'`. Not sure if that's possible.

### Your environment

<!-- PLEASE FILL THIS OUT -->

| Software    | Version(s) |
| ----------- | ---------- |
| fp-ts       |    2.6.1   |
| io-ts       |    2.2.3   |
| io-ts-types |    0.5.6   |
| TypeScript  |    3.9.3   |

### Additional contract requirements

- Existing codecs and combinators must be available as named imports from `io-ts-types/lib`, including `fromNullable` and `DateFromISOString`.
