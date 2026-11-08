📝 Documentation: It's "pre-commit", not "precommit"
### Bug Report Checklist

- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

The file is `.husky/pre-commit`:

https://github.com/JoshuaKGoldberg/create-typescript-app/blob/e65eae3e00d797ce0d88b5a1eb9707c857c66944/docs/FAQs.md?plain=1#L91

This explains why it's showing up in `cspell.json`'s `words`.

### Additional Info

Split out of #1670.

:sparkling

### Additional contract requirements

- The FAQ entry about the Husky hook should refer to the hook as `.husky/pre-commit`, not `.husky/precommit`.
- The obsolete spelling `precommit` should no longer be listed in the `words` of `cspell.json`.
