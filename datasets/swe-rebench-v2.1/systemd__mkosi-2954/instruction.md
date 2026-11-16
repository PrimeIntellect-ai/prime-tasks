Add an executable version of `mkosi.version`
Originally proposed by @septatrix in https://github.com/systemd/mkosi/pull/2905#issuecomment-2251456448

This is effectivly a version of `mkosi.version` that is executed and its output on `stdout` is used as `ImageVersion=`, instead of using the contents of the file for the version.

This would for example allow writing a script that roughly contains `exec git describe --tags --dirty --broken` to use a versioning scheme that is defined by `git tag`, without needing to run `mkosi bump` (with the linked PR) to update the version file before every build.
