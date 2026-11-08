🐛 Bug: Exempt repository admins from branch ruleset merge requirements
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

Back before #1309 -> #1788, when branch protections were set, they exempted repository admins -e.g. me on this repo- from being blocked on merging. I would expect that to remain the same.

### Actual

After #1788, repo admins are blocked too.

### Additional Info

I'd wanted to set this intentionally at first to make things more strict. Strictness good!

I was hoping the UI would make it easier for admins to bypass. But no, there's just ... nothing on there I can see. I'd planned on trying this out for longer but it's _really_ annoying. Ah well.

💖
