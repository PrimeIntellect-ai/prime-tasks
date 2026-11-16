🐛 Bug: package.json files should deduplicate clear directory subsets
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

If `blockPackageJson` is being told to print:

```json
"files": [
	"LICENSE.md",
	"README.md",
	"lib/",
	"lib/bin/pjv.mjs"
]
```

...then it should know to remove `"lib/bin/pjv.mjs"`. It's clearly matched by the earlier `"lib/"`.

### Actual

https://github.com/JoshuaKGoldberg/package-json-validator/pull/178/files#r2024966892 shows that this is not the case right now.


### Additional Info


🎁
