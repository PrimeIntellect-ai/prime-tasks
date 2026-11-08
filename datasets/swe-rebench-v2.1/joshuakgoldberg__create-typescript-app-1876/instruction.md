🐛 Bug: File permissions in blockPrettier don't match what fs.stat reads
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

`blockPrettier` should create files with a chmod mode that stays the same after `fs.stat` reads them.

### Actual

Running `fs.statSync(".husky/pre-commit").mode` gives `mode: 33279`. Converting that `.toString(16)` gives `81ff`. `.toString(8)` gives `100777`. Which visually matches the `777` I'm trying to write them as.

🤷

### Additional Info

I don't want to dive deep into file permissions bits/integers now. So I'll just go with it.

Prototyped in #1839.

💖
