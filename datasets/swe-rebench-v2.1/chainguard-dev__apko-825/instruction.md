some publish options (eg --package-version-tag) broken in 0.9.0
/I believe something happened between 0.8.0 and 0.9.0 that caused some `apko publish` flags to stop working. The first one I noticed is `--package-version-tag` but I believe others might be impacted such as `--package-version-tag-stem`

I am still digging into the code but right now I am assuming this may have happened in or around the build/publish unification PR https://github.com/chainguard-dev/apko/pull/724 when much of the Opts handling in PublishCmd() changed.

Reproduce:
```yaml
contents:
  keyring:
    - https://packages.wolfi.dev/os/wolfi-signing.rsa.pub
  repositories:
    - https://packages.wolfi.dev/os
  packages:
    - git
    - git-lfs
    - openssh-client

entrypoint:
  command: /usr/bin/git

work-dir: /home/git

accounts:
  groups:
    - groupname: git
      gid: 65532
  users:
    - username: git
      uid: 65532
      gid: 65532

archs:
  - x86_64
  - aarch64
```

Using both 0.8.0 and 0.9.0, observe that 0.8.0 adds additional tags from the `git` package and 0.9.0 does not:

```console
$ apko publish --debug --package-version-tag=git ./apko.yaml  registry/git:latest --arch host
```

In 0.8.0 this will be seen in the output:
```
❕           | Found version, images will be tagged with 2.41.0-r0
ℹ️            | Returning additional tags [registry/git:2.41.0-r0]
```

I believe other functionality related to `additionalTags` is likely broken too but I have not tested, likely `--package-version-tag-stem`.

I am still digging into the code but since I am unfamiliar with it I am not sure the route to resolve this issue yet. [HIDDEN]

~Also, I have noticed the `--sbom` flag to `publish` seems to be broken on 0.8.0 and 0.9.0 as neither of them will produce separate SBOM files on disk (.sbom layers are built and published) and report `WantSBOMS = false` in the debug output.~

### Additional contract requirements

- Add a public function `AdditionalTags(pkgs []*apk.InstalledPackage, logger log.Logger, tags []string, packageVersionTag, packageVersionTagPrefix, tagSuffix string, packageVersionTagStem bool) ([]string, error)` in package `pkg/apk` (file `pkg/apk/apk.go`). `apk.InstalledPackage` is the installed-package type from `github.com/chainguard-dev/go-apk/pkg/apk`, and `log.Logger` is from `chainguard.dev/apko/pkg/log`.
- `apko publish --package-version-tag=<package>` must publish the image under additional references derived from the version of the named installed package (for example `registry/git:2.41.0-r0`), in addition to the references given on the command line.
- For `AdditionalTags`, apply `packageVersionTagPrefix` before each generated version tag and append `tagSuffix` to each generated tag. When `packageVersionTagStem` is true, return the full version tag first, followed by tags formed by progressively removing trailing dot-separated version components. For example, version `10.45.6-r5` with prefix `bam-` and suffix `-boom` produces `bam-10.45.6-r5-boom`, `bam-10.45.6-boom`, `bam-10.45-boom`, and `bam-10-boom`, in that order.
