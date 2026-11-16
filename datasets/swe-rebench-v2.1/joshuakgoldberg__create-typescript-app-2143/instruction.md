🐛 Bug: Transition mode clobbers existing README.md content after badges if there is no Usage h2
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

Following #2127 -> #2128, running `npx create-typescript-app` in an existing repo shouldn't remove any content between badges and `## Usage`.

### Actual

https://github.com/JoshuaKGoldberg/prune-github-notifications/pull/201/files#r2028676849 shows sections being removed. Again. Ugh.

### Additional Info

🎁

### Additional contract requirements

In transition mode, when an existing README has no `## Usage` heading, its explanatory content after the badges must be retained in the generated README.
