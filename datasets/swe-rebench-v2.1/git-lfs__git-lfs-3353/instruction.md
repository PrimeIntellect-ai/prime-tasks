git-lfs asks for a password for SSH push urls with an HTTPS fetch url
I have my remote URL set to `prefix:username/repo` where `prefix:` is configured as:

```ini
[url "https://somesite.com/"]
    insteadOf = prefix:
[url "ssh://somesite.com/"]
    pushInsteadOf = prefix:
    insteadOf = prefixpriv:
```

When pushing with LFS data, LFS tries to communicate over the HTTPS URL, requesting a username and password. If I set it to `prefixpriv:`, everything works fine (GitLab mentions something about passing the credentials over from SSH to the HTTPS communication). When pushing, `git-lfs` should query using [HIDDEN] and when pulling it should query with [HIDDEN]

### Additional contract requirements

- When LFS resolves the endpoint for an upload, it must use the remote's push URL; when it resolves the endpoint for a download, it must use the remote's ordinary fetch URL.
- `pushInsteadOf` aliases must be honored when resolving upload URLs. Ordinary `insteadOf` aliases must still be honored for downloads, and for uploads when no push-specific alias applies.
