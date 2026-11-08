🚀 Feature: Disable previous `main` branch protection in transition mode
### Feature Request Checklist

- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

As of #1309 -> #1788, this template uses GitHub repository rulesets instead of branch protections. But older repos made with the template may still be using a `main` branch protection.

Let's have `blockRepositoryBranchRuleset` send a request to disable any existing `main` branch protection as part of its `transition()`.

### Additional Info

If possible, it'd be good to _disable_ and not _delete_ the branch protection. Just in case there was something there folks wanted.

🎁
