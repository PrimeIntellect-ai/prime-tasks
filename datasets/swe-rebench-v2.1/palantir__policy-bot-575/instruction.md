Re-add SSH signature support
Support for SSH signatures was added in #504 and reverted in #507. The required `SshSignature` GraphQL type is only available in GitHub.com and GitHub Enterprise 3.7 and newer. On GHE 3.6 (what we're currently running internally), all evaluations fail with this error:

```
failed to compute approval status: failed to list commits: failed to load commits: No such type SshSignature, so it can't be a fragment condition
```

I reverted the feature to unblock other fixes, but we should add it again if either:

1. We also add feature detection so that it is only enabled when GitHub supports it
2. We upgrade to GHE 3.7 internally and are ready to drop support for older versions in Policy Bot

### Additional contract requirements

SSH-signature support is available for GitHub.com and GitHub Enterprise 3.7 or newer. GitHub Enterprise 3.6 and older are not supported; installations must be upgraded to a version that provides the `SshSignature` GraphQL type before using this version of Policy Bot.
