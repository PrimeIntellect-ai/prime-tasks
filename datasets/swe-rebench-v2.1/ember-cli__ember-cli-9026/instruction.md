Tracked properties module not included in new ember projects
---

Output from `ember version --verbose && npm --version && yarn --version`:
```
ember-cli: 3.15.1
http_parser: 2.8.0
node: 10.13.0
v8: 6.8.275.32-node.36
uv: 1.23.2
zlib: 1.2.11
ares: 1.14.0
modules: 64
nghttp2: 1.34.0
napi: 3
openssl: 1.1.0i
icu: 62.1
unicode: 11.0
cldr: 33.1
tz: 2018e
os: darwin x64
6.4.1
1.12.3
```

The [guides](https://guides.emberjs.com/v3.15.0/upgrading/current-edition/tracked-properties/) imply that tracked properties are included out of the box in a new ember-cli project.

However, generating a new ember-cli project on 3.15 does not include the module @glimmer/tracking -- leading to confusion for users.

Should a new ember-cli project include @glimmer/tracking?
