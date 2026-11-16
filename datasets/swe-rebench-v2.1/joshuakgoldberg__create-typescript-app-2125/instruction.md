🐛 Bug: README.md additional content should ignore older "this package is based on" notices
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

Older CTA repos used "templated by" notice like:

```md
> 💙 This package is based on [@JoshuaKGoldberg](https://github.com/JoshuaKGoldberg)'s [create-typescript-app](https://github.com/JoshuaKGoldberg/create-typescript-app).
```

This should be omitted when running `npx create-typescript-app` in transition mode

### Actual

https://github.com/JoshuaKGoldberg/should-semantic-release/pull/547/files#r2026952619: it's not.

### Additional Info

🎁
