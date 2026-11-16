🐛 Bug: .all-contributorsrc switched to tabs instead of spaces during migration
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

As noted in #2001, all-contributors/app PRs send with two spaces as indentation in `.all-contributorsrc`. `npx create-typescript-app` should apply the same.

### Actual

Presently, it is not - it formats with `\t` per Prettier settings.

### Additional Info

Example swaparoo: https://github.com/JoshuaKGoldberg/all-contributors-for-repository/pull/773

🎁
