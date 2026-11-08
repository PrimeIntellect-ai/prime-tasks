`file_info.mode` is not inherited when using `type: tree`
### What happened?

When I package a RPM and DEB, and use `type: tree`,  subdirectories and files do not apply `file_info.mode` property

 `file_info.owner` and `file_info.group` are working fine (applied to subdirectories and files)

### How can we reproduce this?

* Create following file structure :
  * A/B/C.txt (0644)

* Create my-package.yaml :
```
name: my-package
arch: "all"
platform: "linux"
version_schema: "none"
version: "1.0.0"
release: "1"
section: "default"
priority: "optional"
maintainer: "kduret"
description: |
  This is a test package.
  Commit: my-commit-hash
vendor: "kduret"
homepage: "https://www.google.com"
license: "Apache-2.0"

contents:
  - src: "./A"
    dst: "/usr/share/A"
    type: tree
    file_info:
      mode: 0775
```

* run following nfpm command : `nfpm package --config my-package.yaml --packager rpm`

* Install generated rpm : `rpm -Uvh my-package-1.0.0-1.rpm`

* Received result :
  * `A/B/C.txt` file is 0644
  * `A/B` directory rights are wrong

* Expected result :
  * `A/B/C.txt` file is 0755
  * `A/B` directory is 0755

### nfpm version

```bash
_____ ____  __  __
 _ __ |  ___|  _ \|  \/  |
| '_ \| |_  | |_) | |\/| |
| | | |  _| |  __/| |  | |
|_| |_|_|   |_|   |_|  |_|
nfpm: a simple and 0-dependencies deb, rpm, apk and arch linux packager written in Go
https://nfpm.goreleaser.com

GitVersion:    2.35.2
GitCommit:     19f03e44c39065d55675c04c794c1668801e1f06
GitTreeState:  false
BuildDate:     2024-01-05T01:57:36Z
BuiltBy:       goreleaser
GoVersion:     go1.21.5
Compiler:      gc
ModuleSum:     h1:/8dAMJ/eG9mFCgN5Q2L3gMheChXmxF9Ue5Nvd5NpnpA=
Platform:      linux/amd64
```
```


### Search

- [X] I did search for other open and closed issues before opening this.

### Code of Conduct

- [X] I agree to follow this project's Code of Conduct

### Additional context

_No response_

### Additional contract requirements

- For a `type: tree` entry, descendant files and subdirectories should receive the explicitly configured `file_info.mode` verbatim. Thus, the reproduction’s `0775` setting means `0775` for those descendants, not `0755`.
