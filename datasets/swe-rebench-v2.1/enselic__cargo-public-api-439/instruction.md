Support sparse creates.io registry
When enabling sparse registry, I consistently got this error:
```
Error: The repo at path /home/codespace/.cargo/registry/index/github.com-1ecc6299db9ec823 is unusable due to having an invalid HEAD reference: reference 'refs/heads/main' not found; class=Reference (4); code=NotFound (-3)
```
Once disabled, and recreating the registry (rming it then cargo fetch) it works.

Command: `cargo public-api diff latest`
