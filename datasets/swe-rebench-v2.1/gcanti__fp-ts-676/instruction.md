Array map is unsafe (Regression)
We've switched back to standard Js array map function.
I've seen some code breaking due to that change.

Here's a repro:

```typescript
describe('array map is unsafe', () => {
  it('is as unsafe as native array map function', () => {
    interface Foo {
      bar: () => number
    }
    const f = (a: number, x?: Foo) => (x ? `${a}${x.bar()}` : `${a}`)
    const res = array.array.map([1, 2], f) // ERROR: TypeError: x.bar is not a function
    assert.deepEqual(res, ['1', '2'])
  })
})
```
I think `fp-ts` should be safe by default.
In the current state I cannot upgrade and have no means to detect the regressions.

@gcanti do you agree?
