🐛 Bug: Transition mode clobbers cspell.json words
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

If a repo adds `words` defined in its `cspell.json`, they should be preserved across transition mode

### Actual

https://github.com/JoshuaKGoldberg/are-docs-informative/pull/690/commits/8994a52a233d75db0271f4fd2996ee8c6fb8bd00 shows that they are not.

### Additional Info

🎁
