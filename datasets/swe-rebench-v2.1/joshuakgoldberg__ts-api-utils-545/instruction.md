🐛 Bug: isFalsyType should return true for `0n`
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/ts-api-utils/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

given the literal `0n` type, `isFalsyType(type)` should be true.

### Actual

`isFalsyType(type)` is false.

### Additional Info

[HIDDEN]

https://github.com/JoshuaKGoldberg/ts-api-utils/blob/41cd21d41f445448681dd32308a48a004f4717cb/src/types/utilities.ts#L49-L51

See also https://github.com/typescript-eslint/typescript-eslint/pull/10205/files
