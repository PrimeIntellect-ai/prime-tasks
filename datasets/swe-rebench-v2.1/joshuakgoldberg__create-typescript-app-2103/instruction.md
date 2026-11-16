🐛 Bug: README.md additional contents not detected if ALL-CONTRIBUTORS-LIST:END not followed by spellchecker:enable
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

Some older CTA repos end their README.md contributors sections with `<!-- ALL-CONTRIBUTORS-LIST:END -->`, not `<!-- spellchecker: enable -->`. This should be detected by the logic added in #2088 -> #2090.

### Actual

https://github.com/JoshuaKGoldberg/package-json-validator/pull/178/files#r2024947759 shows that it isn't. Only `spellchecker: enable` comments are detected.

### Additional Info

🎁

### Additional contract requirements

Preserve recognition of additional README content following a contributors section identified by a spellchecker enable marker, including when the README has no `ALL-CONTRIBUTORS-LIST:END` marker.
