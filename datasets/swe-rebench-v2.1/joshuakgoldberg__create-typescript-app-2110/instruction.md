🐛 Bug: `blockPackageJson` ignores `addons.type` if provided
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

This should customize the generated `package.json`'s `type`:

```js
blockPackageJson({
	properties: {
		type: "commonjs",
	},
}),
```

### Actual

https://github.com/JoshuaKGoldberg/package-json-validator/pull/178/files#r2025641061 shows a `package.json` with a `type` forcefully set to `"module"`.

### Additional Info

🎁
