[new rule] prefer `await expect(...).resolves`
Pretty much the opposite to the now-deprecated `no-expect-resolves`: prefer doing `await expect(...).resolves` over `expect(await ...)` as it gives a better failure message.

With `resolves`, if the promise rejects it'll fail the assertion, giving you an error on the lines of `expected promise to resolve but it rejected with ...`.
`expect(await ...)` however means that the rejection will be thrown "outside" of the `expect`, giving you a more generic "test thrown an unexpected error" message.

This also affected the behaviour of `expect.hasAssertions` & co, as with `resolves` you'll be hitting an assertion which fails, which is considered a "pass` in the eyes of `hasAssertions`.

I think `prefer-expect-resolves` could be a good name for this new rule.

### Additional contract requirements

- Name the new rule `prefer-expect-resolves`.
