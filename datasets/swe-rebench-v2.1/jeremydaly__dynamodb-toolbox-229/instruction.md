expressionBuilder mutates expressions
Right now `expressionBuilder` will mutate input expressions.
This can be a problem when we reuse prebuilt expressions across multiple queries/entities.
I myself spent couple of hours figuring this out.

Such test
```TypeScript
it("doesn't mutate input expression", () => {
    let exp = { attr: 'a', eq: 'b' }
    expressionBuilder(exp,TestTable,'TestEntity')
    expect(exp).toEqual({ attr: 'a', eq: 'b' })
  }))
```
Will fail with:
```Jest
expect(received).toEqual(expected) // deep equality

    - Expected  - 0
    + Received  + 1

      Object {
        "attr": "a",
    +   "entity": "TestEntity",
        "eq": "b",
      }

      361 |     let exp = { attr: 'a', eq: 'b' }
      362 |     expressionBuilder(exp ,TestTable,'TestEntity')
    > 363 |     expect(exp).toEqual({ attr: 'a', eq: 'b' })
          |                 ^
      364 |   })
      365 | })
      366 |
```
I've submitted a PR with a fix linked below
