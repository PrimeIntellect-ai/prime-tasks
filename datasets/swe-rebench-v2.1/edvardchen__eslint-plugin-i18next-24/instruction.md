Allow regex patterns in ignore lists
Add capability to add regex patterns along with strings in ignore lists.

For example, if I want to ignore all functions starting with "foo" (e.g. "foo()", "foo1()", "fooTwo()") and a function "bar()", I would add:

```js
{ ignoreCallee: [/foo.*/, 'bar'] }

```

This would allow non-exhaustive checks, that is, to ignore a list of items where elements are not known in advance (or tedious to enumerate).

Related to https://github.com/edvardchen/eslint-plugin-i18next/issues/18 (the code will probably be shared)

### Additional contract requirements

- A call such as `i18nextXt("taa")` must be reported as a literal-string violation.
