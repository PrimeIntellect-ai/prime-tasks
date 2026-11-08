Extra check for incompatible options
<!--
Thank you for suggesting an idea to make this project better!

Please fill in as much of the template below as you're able.
-->

**Is your feature request related to a problem? Please describe.**

https://github.com/lirantal/lockfile-lint/issues/23#issuecomment-569302102

```
> nodejs.org@ test:lint:lockfile C:\Users\xmr\Desktop\nodejs.org
> lockfile-lint --allowed-hosts npm github.com --allowed-schemes "https:" "git+https:" --empty-hostname false --validate-https --type npm --path package-lock.json

detected invalid protocol for package: metalsmith-permalinks@git+https://github.com/segmentio/metalsmith-permalinks.git#432843d5823a292b2e47397ba46fd761d03eb9d3
    expected: https:
    actual: git+https:

error: command failed with exit code 1
```

**Describe the solution you'd like**

Since the above works without the `validate-https` flag, maybe there should be some checks in place for potentially incompatible options.

### Additional contract requirements

- When `--allowed-schemes` and `--validate-https` are provided together, the CLI must write `Arguments o and validate-https are mutually exclusive` to stderr.
