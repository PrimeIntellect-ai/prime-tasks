New: meta-property-ordering
similar to rule test-case-property-ordering, but it aims to check the ordering rule meta.

not sure if it can enforce the exsistence of some properties (e.g. fixalbe, docs, messages), or another rule?

### Additional contract requirements

- The rule is exposed as the module `lib/rules/meta-property-ordering.js`.
- By default, the `meta` property order is `type`, `docs`, `fixable`, `schema`, `messages`.
- For an ordering violation, use the message `The meta properties should be placed in a consistent order: [<order>].`, joining the expected property names with `, `.
