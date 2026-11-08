Avoid detecting text of type union.
We would like to prevent Lint from detecting values with the union type specified, as shown below.
Currently, it is detected as an error.

```ts
type Animal = 'dog' | 'cat'

const animal: Animal = 'dog' -> disallow literal string: sample: Animal = 'dog'eslint(i18next/no-literal-string)
```

---

This PR https://github.com/edvardchen/eslint-plugin-i18next/pull/56 has been deleted in what appears to be the relevant code. Do you plan to implement similar changes again?
