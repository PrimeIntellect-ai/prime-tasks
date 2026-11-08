`[[targets.distros]]` in `buildpack.toml` is ignored if the run image distro name/version isn't available
### Summary

The Buildpack API 0.10 spec says:

> Metadata specified in `[[targets]]` is validated against the runtime and build-time base images.
> * A buildpack target satisfies a base image target when `os`, `arch`, and `variant` match and at least one distribution in `distros` (if provided) matches

(https://github.com/buildpacks/spec/blob/buildpack/v0.10/buildpack.md#targets)

As such, if a buildpack's `buildpack.toml` contains:

```toml
[[targets]]
os = "linux"
arch = "amd64"

[[targets.distros]]
name = "ubuntu"
version = "123"
```

...then I would expect the buildpack to only pass detection if the run image's distro name was "ubuntu" and version was "123".

However, it seems that if the distro name/version could not be determined by `lifecycle` (for example, the run image doesn't have the `io.buildpacks.base.distro.*` Docker labels set and the `/etc/os-release` fallback isn't available or [is broken](https://github.com/buildpacks/lifecycle/issues/1336)), then `lifecycle` ignores the `[[targets.distros]]` requirements and instead matches against any distro.

[HIDDEN]

---

### Reproduction

##### Steps

1. `pack buildpack new testcase-buildpack-targets --api 0.10 --targets "linux/amd64"`
1. `echo -e '\n[[targets.distros]]\nname = "ubuntu"\nversion = "123"' >> testcase-buildpack-targets/buildpack.toml`
1. `pack build --builder heroku/builder:22 --run-image heroku/heroku:22-cnb.v122 --buildpack testcase-buildpack-targets/ --path testcase-buildpack-targets/ testapp --verbose`

##### Current behavior

Buildpack detection unexpectedly passes:

```
$ pack build --builder heroku/builder:22 --run-image heroku/heroku:22-cnb.v122 --buildpack testcase-buildpack-targets/ --path testcase-buildpack-targets/ testapp --verbose
...
===> ANALYZING
...
Run image info in analyzed metadata is:
{"Reference":"6d5f868e91eba6a6ec22a9a9b9b31a2fd486a0f0f57082fd0864e0bf0b3e4395","Image":"heroku/heroku:22-cnb.v122","Extend":false,"target":{"os":"linux","arch":"amd64"}}
===> DETECTING
...
Checking for match against descriptor: {linux amd64  [{ubuntu 123}]}
======== Results ========
pass: testcase-buildpack-targets@1.0.0
```

...even though the buildpack declares that it only supports:

```
[[targets.distros]]
name = "ubuntu"
version = "123"
```

...and the run image's Ubuntu version is not "123".

##### Expected behavior

I would expect buildpack detection to fail, like how it fails if I use a newer version of our run image (by omitting the `--run-image heroku/heroku:22-cnb.v122` argument) that has the relevant `io.buildpacks.base.distro.*` Docker labels set:

```
$ pack build --builder heroku/builder:22 --buildpack testcase-buildpack-targets/ --path testcase-b
uildpack-targets/ testapp --verbose
...
===> ANALYZING
...
Run image info in analyzed metadata is:
{"Reference":"9e85c0884ff5a53485a1f53e4c3f958811ea755ddb24885e55b2bcdec2ddf7f1","Image":"heroku/heroku:22-cnb","Extend":false,"target":{"os":"linux","arch":"amd64","distro":{"name":"ubuntu","version":"22.04"}}}
===> DETECTING
...
Checking for match against descriptor: {linux amd64  [{ubuntu 123}]}
======== Error: testcase-buildpack-targets@1.0.0 ========
unable to satisfy target os/arch constraints; run image: {"os":"linux","arch":"amd64","distro":{"name":"ubuntu","version":"22.04"}}, buildpack: [{"os":"linux","arch":"amd64","distros":[{"name":"ubuntu","version":"123"}]}]
======== Results ========
err:  testcase-buildpack-targets@1.0.0
```

---

### Context

##### lifecycle version
`0.19.3`

##### platform version(s)

```
$ pack report
Pack:
  Version:  0.33.2+git-f2cffc4.build-5562
  OS/Arch:  darwin/arm64
```

The build is using Platform API 0.12 and Buildpack API 0.10.

### Additional contract requirements

- If a buildpack declares distro constraints and the run image's distro metadata cannot be determined, the target must not be considered satisfied; detection must reject that target.
