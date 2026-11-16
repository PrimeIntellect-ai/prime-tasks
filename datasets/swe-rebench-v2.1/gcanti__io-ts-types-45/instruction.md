Relax fromNewtype signature
```ts
interface Id extends Newtype<'Id', string> {}

const Id = fromNewtype<Id>(t.string)

interface User {
  id: Id
  name: string
}

const User = t.interface({
  id: Id,
  name: t.string
})

interface SpecialUser extends Newtype<'SpecialUser', User> {}

const SpecialUser = fromNewtype<SpecialUser>(User) // static error: Type 'string' is not assignable to type 'Id'
```

This is due to `O` being restricted to `CarrierOf<N>`

```ts
export const fromNewtype: <N extends AnyNewtype>(
  type: Type<CarrierOf<N>, CarrierOf<N>, mixed>
) => Type<N, CarrierOf<N>, mixed> = type => type as any
```

Proposed solution: add a `fromNewtypeCurried` function when `O` is free

[HIDDEN]

### Additional contract requirements

- Add `fromNewtypeCurried` as a curried constructor: the first call selects the target newtype, and the returned function accepts a codec that decodes to that newtype’s carrier and encodes to an independent representation. The resulting codec must decode to the newtype and preserve the supplied codec’s encoded representation when encoding.
