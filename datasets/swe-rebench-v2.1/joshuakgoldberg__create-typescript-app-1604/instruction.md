🚀 Feature: Increase Renovate minimumReleaseAge to 7 days
### Bug Report Checklist

- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

For a while now, this template has set Renovate's `minimumReleaseAge` to `3 days`. That's the time threshold for an npm package to be unable to be unpublished. It also has the nice benefit of giving some time for the community to catch & patch a malicious version of a previously ok package.

But, 3 days isn't a super long amount of time. If something releases on a Friday then folks might not have fully caught+patched it by Monday. I've been thinking for a while of increasing it to a full week.

[HIDDEN]

### Additional Info

See docs on: https://docs.renovatebot.com/configuration-options/#minimumreleaseage

### Additional contract requirements

- Renovate's minimum release age must be seven days in the repository's Renovate settings and in the Renovate settings produced by this template.
