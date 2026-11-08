🛠 Tooling: Post release action doesn't work after initial release
### Bug Report Checklist

- [X] I have tried restarting my IDE and the issue persists.
- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

Consider this post-release GitHub Action: https://github.com/johnnyreilly/ado-npm-auth-lite/actions/workflows/post-release.yml

After the initial run all subsequent runs fail with this error:

```
Error: HttpError: Resource not accessible by integration
Error: Resource not accessible by integration
```

Is this a "me" thing?  I don't think I've done anything to that and so I'm wondering if I've stumbled on somthing.

Here's the initial successful run: https://github.com/johnnyreilly/ado-npm-auth-lite/actions/runs/11732080037/job/32683543794

### Additional Info

n/a

### Additional contract requirements

The generated post-release workflow must give its release job sufficient GitHub token access to create or update release comments on both issues and pull requests, so subsequent published releases do not fail with “Resource not accessible by integration.”
