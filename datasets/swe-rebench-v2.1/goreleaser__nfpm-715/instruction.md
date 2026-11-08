RPM cpio name contains the release twice
### What happened?

Hi, in v2.33.0, there is a new bug regarding the generation of an RPM.
using the minimal description file attached, the generated RPM is called `test-1.2.3-1.x86_64.rpm` (correct) but contains `test-1.2.3-1-1.x86_64.cpio` (not correct, release is used twice).
With v2.32.0, the rpm and cpio are correctly named.

### How can we reproduce this?

test.yaml :
```
name: "test"
version: 1.2.3
contents:
  - src: test
    dst: test
```
` go install github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.33.0`
` nfpm pkg --config test.yaml --packager rpm`

### nfpm version

```bash
_____ ____  __  __
 _ __ |  ___|  _ \|  \/  |
| '_ \| |_  | |_) | |\/| |
| | | |  _| |  __/| |  | |
|_| |_|_|   |_|   |_|  |_|
nfpm: a simple and 0-dependencies deb, rpm, apk and arch linux packager written in Go
https://nfpm.goreleaser.com

GitVersion:    dev
GitCommit:     unknown
GitTreeState:  unknown
BuildDate:     unknown
BuiltBy:       unknown
GoVersion:     go1.21.1
Compiler:      gc
ModuleSum:     h1:yBv6jgkPwih4va/S42rceSjJ2Znt3Og/Ntc76oP0tfI=
Platform:      windows/amd64
```


### Search

- [X] I did search for other open and closed issues before opening this.

### Code of Conduct

- [X] I agree to follow this project's Code of Conduct

### Additional context

_No response_

### Additional contract requirements

- The generated RPM's VERSION field must contain only the version, excluding the release: use `1.0.0` (not `1.0.0-1`), `1.0.0~rc1` (not `1.0.0~rc1-1` or `1.0.0~rc1-2`), and `1.0.0+meta` (not `1.0.0+meta-1` or `1.0.0+meta-10`); the release is reported separately.
