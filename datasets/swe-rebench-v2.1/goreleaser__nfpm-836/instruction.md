Invalid RPM version strings when version contains multiple '-'
### What happened?

nfpm can produce RPMs with an invalid verison field.  This happens when the version contains multiple hyphens, e.g. `1.2.3-alpha-beta-gamma`. nfpm will identify `alpha-beta-gamma` as the prerelease and correctly join it with the version using a tilde, producing `1.2.3~alpha-beta-gamma`. However, this version is invalid because hyphens are not allowed in version strings according to the official [RPM documentation](https://rpm-software-management.github.io/rpm/manual/spec.html).

RPM _almost_ handles the version correctly, but since hyphens are used as delimiters for parsing a NEVRA, you hit odd behavior at times:
```bash
$ rpm --dbpath=/tmp/asdf -q ABC --queryformat '%{VERSION}\n'
1.2.3~alpha-beta-gamma
$ rpm --dbpath=/tmp/asdf -q ABC
ABC-1.2.3~alpha-beta-gamma-1.x86_64
$ rpm --dbpath=/tmp/asdf -q ABC-1.2.3~alpha-beta-gamma
package ABC-1.2.3~alpha-beta-gamma is not installed
```

I think nfpm should either
* [HIDDEN]
* Warn the user in some way, but not try to modify the pre-release. Some ideas:
  * Print a warning if the parsed pre-release contains invalid characters
  * Error out if the  parsed pre-release contains invalid characters
  * Put a note in the documentation somewhere about this pitfall

### How can we reproduce this?

nfpm.yaml
```yaml
name: ABC
version: 1.2.4-alpha-beta-gamma
```
`nfpm p -p rpm`

### nfpm version

```bash
Latest main (41b3349)

       _____ ____  __  __
 _ __ |  ___|  _ \|  \/  |
| '_ \| |_  | |_) | |\/| |
| | | |  _| |  __/| |  | |
|_| |_|_|   |_|   |_|  |_|
nfpm: a simple and 0-dependencies apk, arch linux, deb, ipk, and rpm packager written in Go
https://nfpm.goreleaser.com

GitVersion:    dev
GitCommit:     unknown
GitTreeState:  unknown
BuildDate:     unknown
BuiltBy:       unknown
GoVersion:     go1.22.3
Compiler:      gc
ModuleSum:     h1:RUmeEt8OlEVeSzKRrO5Vl5qVWCtUwx4j9uivGuRo5fw=
Platform:      linux/amd64
```


### Search

- [X] I did search for other open and closed issues before opening this.

### Code of Conduct

- [X] I agree to follow this project's Code of Conduct

### Additional context

_No response_

### Additional contract requirements

- The RPM version formed from a version and pre-release must retain the version followed by a tilde, and the pre-release portion of the resulting RPM version must contain no hyphens while retaining its other content.
