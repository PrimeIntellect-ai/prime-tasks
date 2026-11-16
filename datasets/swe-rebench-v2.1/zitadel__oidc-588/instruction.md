Update to go-jose/v4
### Preflight Checklist

- [X] I could not find a solution in the existing issues, docs, nor discussions
- [ ] I have joined the [ZITADEL chat](https://zitadel.com/chat)

### Describe your problem

go-jose/v4 was released about a month ago, with version 4.0.1 fixing CVE-2024-28180. I'd like to update the packaging of this library in Debian, but there was an API change in go-jose/v4 that requires specifying the expected algorithm(s) when calling `ParseSigned()` (https://github.com/go-jose/go-jose/pull/69). It doesn't look that hard to fix, but I'm not familiar enough with the zitadel/oidc codebase to confidently submit a pull request fixing this.

```
# github.com/zitadel/oidc/pkg/oidc
src/github.com/zitadel/oidc/pkg/oidc/verifier.go:151:31: not enough arguments in call to jose.ParseSigned
        have (string)
        want (string, []jose.SignatureAlgorithm)
```

### Describe your ideal solution

Update to go-jose/v4.

### Version

3.19.0

### Environment

Self-hosted

### Additional Context

My ultimate goal is to update zitadel/oidc in Debian so I can package and upload the latest release of [Incus](https://github.com/lxc/incus), which uses this library.
