Tern doesn't split shell commands separated by a ';'
**Describe the bug**
Tern doesn't split shell commands separated by a ';'

**To Reproduce**
1. Run `tern report -i golang:1.12-alpine -f output.txt`
2. See output.txt:
```
        warning:
Unrecognized Commands:set -eux;         apk add --no-cache --virtual .build-deps                bash            gcc             musl-dev                openssl                 go      ;       export          GOROOT_BOOTSTRAP="$(go env GOROOT)"             GOOS="$(go env GOOS)"           GOARCH="$(go env GOARCH)"               GOHOSTOS="$(go env GOHOSTOS)"           GOHOSTARCH="$(go env GOHOSTARCH)"       ;       apkArch="$(apk --print-arch)";  case "$apkArch" in              armhf) export GOARM='6' ;;              x86) export GO386='387' ;;      esac;           wget -O go.tgz "https://golang.org/dl/go$GOLANG_VERSION.src.tar.gz";    echo '2aa5f088cbb332e73fc3def546800616b38d3bfe6b8713b8a6404060f22503e8 *go.tgz' | sha256sum -c -;       tar -C /usr/local -xzf go.tgz;  rm go.tgz;              cd /usr/local/go/src;   ./make.bash;            rm -rf          /usr/local/go/pkg/bootstrap             /usr/local/go/pkg/obj   ;       apk del .build-deps;            export PATH="/usr/local/go/bin:$PATH";  go version
```
**Error in terminal**
No Error

**Expected behavior**
`apk` is a known package manager, so Tern should be able to report all the packages installed by this line. -> `bash gcc musl-dev openssl go`

**Environment you are running Tern on**
Enter all that apply
- VMware Fusion VM running Ubuntu 18.04 LTS

### Additional contract requirements

- The public function `filter_install_commands(shell_command_line)` in module `tern/helpers/common.py` returns a tuple `(command_list, report)`, where `command_list` contains the recognized install and remove `Command` objects parsed from the shell command line. Shell commands separated by `;` are treated as separate commands, so a package manager command that appears after a `;` is recognized and the packages it installs are reported.
- Add a public method `merge(self, other)` to the `Command` class in module `tern/classes/command.py`. It raises `TypeError` when `other` is not a `Command`. It returns `False` when `other` is a `Command` whose `name` differs from the caller's. When `other` is a `Command` with the same `name`, it returns `True`; if `other` is an install command, `other`'s words are added to the caller without duplicates.
