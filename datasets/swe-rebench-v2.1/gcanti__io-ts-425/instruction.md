Getters can satisfy io-ts static types while failing to decode at runtime
## 🐛 Bug report

Given an object validator:

```
type Person = {
  name: string
}

const person: t.Type<Person> = t.strict({
  name: t.string,
})
```

Instances of classes with a `name` attribute will pass runtime validation. But instances of a class with a `name` getter will fail runtime validation because io-ts will see an `undefined` name.

Both of those uses pass the static type checks, even though the second one is rejected at runtime. The net effect is: the type system allows data that will definitely be rejected by io-ts at runtime.

### Reproducible example

This self-contained TypeScript file demonstrates the bug. Alice has a regular `name` property, type checks against `t.TypeOf<typeof person>`, and validates. Bob has a `name` getter, also type checks against `t.TypeOf<typeof person>`, but fails validation at runtime.

```typescript
import * as t from "io-ts"

type Person = {
  name: string
}

class Alice {
  public name: string

  constructor() {
    this.name = 'Alice'
  }
}

class Bob {
  get name() { return 'Bob' }
}

const person: t.Type<Person> = t.strict({
  name: t.string,
})

// Alice has a normal `name` property; we assign her to the type extracted from
// the io-ts validator; and everything works.
const alice: t.TypeOf<typeof person> = new Alice()
console.log("Alice object:", alice)
console.log("Alice decode:", person.decode(alice))
console.log()

// Bob has a `name` getter; again we assign him to the type extracted from the
// io-ts validator; but it fails at runtime even though the types check.
const bob: t.TypeOf<typeof person> = new Bob()
console.log("Bob object:", bob)
console.log("Bob decode:", person.decode(bob))
```

Here's the output that I see:

```
Alice object: Alice { name: 'Alice' }
Alice decode: { _tag: 'Right', right: Alice { name: 'Alice' } }

Bob object: Bob {}
Bob decode: {
  _tag: 'Left',
  left: [ { value: undefined, context: [Array], message: undefined } ]
}
```

### Additional context

Searching issues for "getter" only gives one result that seems unrelated to this, so hopefully this isn't a duplicate!

### Your environment

Which versions of io-ts are affected by this issue? Did this work in previous versions of io-ts?

| Software   | Version(s) |
| ---------- | ---------- |
| io-ts      | 2.1.1           |
| fp-ts      | 2.5.1           |
| TypeScript | 3.8.2           |
