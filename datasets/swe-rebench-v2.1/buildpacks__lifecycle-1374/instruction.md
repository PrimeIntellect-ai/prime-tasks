`CNB_TARGET_ARCH` and `CNB_TARGET_OS` not set correctly when using Platform API 0.9
### Summary

The Buildpack API v0.10 spec says that the `CNB_TARGET_ARCH` and `CNB_TARGET_OS` env vars will always be set:
https://github.com/buildpacks/spec/blob/buildpack/v0.10/buildpack.md#targets

However, this is not the case iff the Platform API is 0.9 or below, even if the buildpack is using Buildpack API 0.10, and the builder is using latest `lifecycle` (which has all the previous fixes for the targets related bugs).

This scenario can occur when a user uses an outdated Pack CLI version that does not support Platform API 0.10, such as Pack CLI v0.27.0 which only supports Platform API <= 0.9.

This came up in:
https://github.com/heroku/buildpacks-php/issues/121

If Buildpack API 0.10 isn't compatible with older Platform APIs, then `lifecycle` should exit with a suitable error message. Otherwise the Buildpack API 0.10 spec should be honoured.

---

### Reproduction

##### Steps

1. Download Pack CLI 0.27.0 (which only supports Platform API <= 0.9), eg : `curl -fL https://github.com/buildpacks/pack/releases/download/v0.27.0/pack-v0.27.0-macos-arm64.tgz | tar -xz && mv ./pack ./pack-0.27.0`
2. `mkdir -p testcase/bin`
3. `echo -e 'api = "0.10"\n\n[buildpack]\nid = "testcase"\nversion = "0.0.1"\n\n[[stacks]]\nid = "*"' > testcase/buildpack.toml`
4. `echo -e '#!/usr/bin/env bash\n\nprintenv | grep CNB_TARGET | sort && exit 1' > testcase/bin/detect`
5. `./pack-0.27.0 build --builder heroku/builder:24 --trust-builder --buildpack testcase/ --path testcase/ testapp --verbose`

##### Current behavior

When using Pack CLI 0.27.0 (which only supports Platform API <= 0.9), the `CNB_TARGET_ARCH` and `CNB_TARGET_OS` env vars are not set correctly (they are set to the empty string, instead of `arm64` and `linux` respectively):

```
$ ./pack-0.27.0 build --builder heroku/builder:24 --trust-builder --buildpack testcase/ --path testcase/ testapp --verbose
Builder heroku/builder:24 is trusted
Pulling image index.docker.io/heroku/builder:24
...
Running the creator on OS linux with:
Container Settings:
  Args: /cnb/lifecycle/creator -daemon -launch-cache /launch-cache -log-level debug -app /workspace -cache-dir /cache -run-image heroku/heroku:24 testapp
  System Envs: CNB_PLATFORM_API=0.9
  Image: pack.local/builder/697477756b6764727773:latest
  User: root
  Labels: map[author:pack]
Host Settings:
  Binds: pack-cache-library_testapp_latest-64516644bb6c.build:/cache /var/run/docker.sock:/var/run/docker.sock pack-cache-library_testapp_latest-64516644bb6c.launch:/launch-cache pack-layers-vtzzazmhya:/layers pack-app-ogpwkrqjst:/workspace
  Network Mode:
Starting creator...
Parsing inputs...
Ensuring privileges...
Executing command...
===> ANALYZING
Timer: Analyzer started at 2024-07-04T13:51:51Z
Image with name "testapp" not found
Found image with identifier "a35bef8f087d6c0804bc83511d01b01b2d203389168e705d2f61921f7b256bab"
Timer: Analyzer ran for 18.375µs and ended at 2024-07-04T13:51:51Z
Run image info in analyzed metadata is:
{"Reference":"a35bef8f087d6c0804bc83511d01b01b2d203389168e705d2f61921f7b256bab","Image":"","Extend":false}
===> DETECTING
Timer: Detector started at 2024-07-04T13:51:51Z
target distro name/version labels not found, reading /etc/os-release file
======== Output: testcase@0.0.1 ========
CNB_TARGET_ARCH=
CNB_TARGET_ARCH_VARIANT=
CNB_TARGET_DISTRO_NAME=ubuntu
CNB_TARGET_DISTRO_VERSION=24.04
CNB_TARGET_OS=
...
```

Compare this to when latest Pack CLI is used, which supports Platform API 0.10:

```
$ pack build --builder heroku/builder:24 --trust-builder --buildpack testcase/ --path testcase/ testapp --verbose
Builder heroku/builder:24 is trusted
Pulling image index.docker.io/heroku/builder:24
...
Running the creator on OS linux from image pack.local/builder/76726b63726261776e7a:latest with:
Container Settings:
  Args: /cnb/lifecycle/creator -daemon -launch-cache /launch-cache -log-level debug -app /workspace -cache-dir /cache -run-image heroku/heroku:24 testapp
  System Envs: CNB_PLATFORM_API=0.13
  Image: pack.local/builder/76726b63726261776e7a:latest
  User: root
  Labels: map[author:pack]
Host Settings:
  Binds: pack-cache-library_testapp_latest-64516644bb6c.build:/cache /var/run/docker.sock:/var/run/docker.sock pack-cache-library_testapp_latest-64516644bb6c.launch:/launch-cache pack-layers-vzajudrqdn:/layers pack-app-wsqlwyuuoc:/workspace
  Network Mode:
Starting creator...
Parsing inputs...
Ensuring privileges...
Executing command...
===> ANALYZING
Timer: Analyzer started at 2024-07-04T13:51:30Z
Image with name "testapp" not found
Found image with identifier "a35bef8f087d6c0804bc83511d01b01b2d203389168e705d2f61921f7b256bab"
Timer: Analyzer ran for 21.084µs and ended at 2024-07-04T13:51:30Z
Run image info in analyzed metadata is:
{"Reference":"a35bef8f087d6c0804bc83511d01b01b2d203389168e705d2f61921f7b256bab","Image":"heroku/heroku:24","Extend":false,"target":{"os":"linux","arch":"arm64","distro":{"name":"ubuntu","version":"24.04"}}}
===> DETECTING
Timer: Detector started at 2024-07-04T13:51:30Z
Checking for match against descriptor: {   []}
======== Output: testcase@0.0.1 ========
CNB_TARGET_ARCH=arm64
CNB_TARGET_ARCH_VARIANT=
CNB_TARGET_DISTRO_NAME=ubuntu
CNB_TARGET_DISTRO_VERSION=24.04
CNB_TARGET_OS=linux
...
```

##### Expected behavior

Either:
1. Lifecycle should honour the Buildpack API 0.10 specification regardless of the Platform API version - and set `CNB_TARGET_ARCH` and `CNB_TARGET_OS` correctly.
2. Or, lifecycle should fail the build with a clear error message that explains the current combination of Platform API and Buildpack API versions are not compatible, and the user should try upgrading their tools.

---

### Context

##### lifecycle version

```
$ pack builder inspect heroku/builder:24
...
Lifecycle:
  Version: 0.19.7
  Buildpack APIs:
    Deprecated: (none)
    Supported: 0.7, 0.8, 0.9, 0.10, 0.11
  Platform APIs:
    Deprecated: (none)
    Supported: 0.7, 0.8, 0.9, 0.10, 0.11, 0.12, 0.13
```

##### platform version(s)

```
$ ./pack-0.27.0 report
Pack:
  Version:  0.27.0+git-f4f5be1.build-3382
  OS/Arch:  darwin/arm64

Default Lifecycle Version:  0.14.1

Supported Platform APIs:  0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9
...
```

### Additional contract requirements

- Lifecycle must set `CNB_TARGET_OS` and `CNB_TARGET_ARCH` to the correct values even when the Platform API version is 0.9 or below. When the target metadata does not already contain an OS or architecture, lifecycle must still produce `CNB_TARGET_OS=linux` and `CNB_TARGET_ARCH` set to the architecture lifecycle is running on.
- The target environment must contain only variables with non-empty values. In particular, `CNB_TARGET_ARCH_VARIANT`, `CNB_TARGET_DISTRO_NAME`, and `CNB_TARGET_DISTRO_VERSION` must be omitted when their values are empty.
