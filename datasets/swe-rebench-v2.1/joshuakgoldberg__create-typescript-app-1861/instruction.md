🐛 Bug: Knip config files don't need !s
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

This template shouldn't include unnecessary `!`s in `knip.json` files.

### Actual

It does, still, for some reason that has been lost to time.

https://github.com/JoshuaKGoldberg/create-typescript-app/blob/5bd6122ec257fd13f8e81492b00f634a21649ac4/knip.json#L3

https://github.com/JoshuaKGoldberg/create-typescript-app/blob/5bd6122ec257fd13f8e81492b00f634a21649ac4/knip.json#L6

I'll go ahead and remove those.

### Additional Info

Prototyped in #1839.

💖
