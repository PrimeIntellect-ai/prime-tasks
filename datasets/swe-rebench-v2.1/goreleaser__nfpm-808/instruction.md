[apk] Misleading documentation for apk.signature.key_name
### What happened?

The [documentation](https://nfpm.goreleaser.com/configuration/) says the following about this attribute:

```md
# The name of the signing key. When verifying a package, the signature
# is matched to the public key store in /etc/apk/keys/<key_name>.rsa.pub.
# If unset, it defaults to the maintainer email address.
```
However, this is incorrect. As evident from the [code](https://github.com/goreleaser/nfpm/blob/a5376659a97b3c9b99cd45e5f5e84913ce3fa498/apk/apk.go#L292), nfpm will add the `.rsa.pub` extension in case of unset key_name only. `apk`, on its side, also doesn't add this extension when looking for the key. So this results in key lookup error in apk.

[HIDDEN]

### How can we reproduce this?

prepare the signed apk package with config like
```yaml
# ...
apk:
  signature:
    key_file: xxxx.rsa
    key_name: xxxx
```
omitting the `.rsa.pub` extension in `key_name`. Try installing this package with `apk add`.

### nfpm version

```bash
the one from https://github.com/goreleaser/nfpm/pull/804 (so git main, essentially)
```


### Search

- [X] I did search for other open and closed issues before opening this.

### Code of Conduct

- [X] I agree to follow this project's Code of Conduct

### Additional context

_No response_

### Additional contract requirements

When a configured APK signing key name omits `.rsa.pub`, the generated signature key name must include that suffix.
