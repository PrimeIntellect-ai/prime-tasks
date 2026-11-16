Can `t.partial` imply `{}`, not all JS objects
## 🚀 Feature request

### Current Behavior

To create a type that _disallows_ arrays but permissively _allows_ objects (using `t.partial`) I need to:

```ts
// There may be another way...
t.intersection([
    t.partial({
      my: t.string,
      permissive: t.string,
      type: t.string,
    }),
    t.brand(
      t.UnknownRecord,
      (v: any): v is t.Branded<any, NotArray> => !Array.isArray(v),
      'NotArray'
    ),
  ])
```

Without using `t.brand` and `t.intersection`, `t.partial` will allow arrays to pass "decode" step at runtime :c .

### Desired Behavior

I would like a way to be able to _negate_ certain runtime types (not static types) _or_ `t.partial` should imply objects `{}`, not arrays `[]`, even though:

```
 😅
typeof []
=> "object"
```

### Suggested Solution

Can `t.partial` by default not allow non-object types? If I would like to use an array type I can reach for `t.array`.

Or, less good:
```ts
// this seems not great, but less verbose than we currently have?
t.intersection([
    t.partial({
      my: t.string,
      permissive: t.string,
      type: t.string,
    }),
   t.not.array
  ])
```
<!-- NOTE: Feature Requests without suggested solutions may not be addressed or treated with the same level of urgency as those that have suggested solutions. -->

### Who does this impact? Who is this for?

<!-- Who is this for? All users? TypeScript users? Beginners? Advanced? Yourself? People using X, Y, X, etc.? -->

Everyone!

### Describe alternatives you've considered

<!-- A clear and concise description of any alternative solutions or features you've considered.  -->

See above

### Additional context

<!-- Add any other context or links about the feature request here. -->
None

### Your environment

<!-- PLEASE FILL THIS OUT -->

| Software   | Version(s) |
| ---------- | ---------- |
| io-ts      |       2.0.1     |
| fp-ts      |       2.3.1     |
| TypeScript |      3.7.2      |

### Additional contract requirements

- `t.UnknownRecord` is a codec whose `is(u: unknown): boolean` returns `true` exactly for plain JavaScript objects (for example `{}` and `{ a: 1 }`) and `false` for arrays, boxed primitives such as `new Number()`, `null`, `undefined` and other primitives. Its `decode(u: unknown)` returns a `Right` containing `u` for plain objects and a `Left` with validation errors otherwise.
- `t.partial(props, name?)` rejects arrays: both `is` and `decode` treat an array as invalid.
- `t.record(domain, codomain, name?)` rejects arrays unless the codomain is `t.any`; when the codomain is `t.any`, arrays are accepted.
- `t.type(props, name?)` and its alias `t.interface(props, name?)` validate only plain objects, rejecting arrays and primitives.
