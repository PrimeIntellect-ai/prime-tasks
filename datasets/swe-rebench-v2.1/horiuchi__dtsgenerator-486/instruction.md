Nested oneOf & anyOf keywords are ignored
Hi.
Thanks again for your work and reactivity!

There are three changes left including this one, and after that i'll open an issue about `patternProperties` which currently produces two index signatures sometimes, which is incompatible with ts `strict` mode when the value types don't overlap (disclaimer: i don't have a solution for this one atm).

The corresponding PR introduces a change that [HIDDEN].
This one was actually difficult to find.
I added a few tests, but perhaps it'd need a few more actually.

PR: #486

### Additional contract requirements

- When a `oneOf` schema is nested within another schema, its child alternatives must be represented in the generated TypeScript declaration rather than ignored.
- Apply the same requirement to a nested `anyOf` schema.
