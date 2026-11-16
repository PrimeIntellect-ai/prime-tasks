`record` with a `literal` key fails to decode inside of an `intersection`
### Current Behavior

```ts
const C = t.intersection([
	t.record(t.literal('funky'), t.string),
	t.record(t.string, t.unknown)
])

type C_ = t.TypeOf<typeof C>

/*
type C_ = {
    funky: string;
} & {
    [x: string]: unknown;
}
*/

const lit: C_ = {
	funky: 'key',
	more: 'nope'
} // Compiles fine


C.decode({
	funky: 'hey',
	more: 'nope'
}) // Left
```

### Expected behavior

```ts
C.decode({
	funky: 'hey',
	more: 'nope'
}) // Right
```

<!-- PLEASE FILL THIS OUT -->

| Software   | Version(s) |
| ---------- | ---------- |
| io-ts      | 2.0.1           |
| fp-ts      | 2.1.2      |
| TypeScript | 3.7.2       |

### Additional contract requirements

- When the key domain is enumerable (a string `literal`, a `keyof` object, or a union of such), `record` requires every key of the domain to be present in the input and removes any keys that are not part of the domain from the decoded output.
