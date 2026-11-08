Correctly handle Unicode characters
The regular expressions in this package don’t support unicode characters such as `àçéèù` so `camelCase("Licorne époustouflante")` outputs `licorne époustouflante`.

Perhaps we could add a `transliterate` option that leverages [transliterate](https://www.npmjs.com/package/@sindresorhus/transliterate) so `camelCase("Licorne époustouflante", { transliterate: true })` outputs `licorneEpoustouflante`.

Another slightly more complicated alternative would be to have `camelCase("Licorne époustouflante", { transliterate: true })` output `licorneÉpoustouflante`.

What do you think? I could put a PR together.

### Additional contract requirements

- Accented Latin letters (such as `àçéèù`) are handled like ASCII letters, so `camelCase('Licorne époustouflante')` outputs `licorneÉpoustouflante`.
- A separator (space, dash, underscore or dot) before an accented Latin letter uppercases that letter, so `camelCase('foo àçéèù')` outputs `fooÀçéèù`.
- With the `pascalCase` option, `camelCase('Licorne époustouflante', {pascalCase: true})` outputs `LicorneÉpoustouflante`.
