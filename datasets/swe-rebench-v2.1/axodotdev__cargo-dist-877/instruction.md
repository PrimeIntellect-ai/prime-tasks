Installing dependencies using apt fails because of outdated info
I've seen a build fail because `apt-get install` fails, seemingly due to outdated package information:

> Run sudo apt-get install libudev-dev
> Reading package lists...
> Building dependency tree...
> Reading state information...
> The following NEW packages will be installed:
>   libudev-dev
> 0 upgraded, 1 newly installed, 0 to remove and 10 not upgraded.
> Need to get 20.7 kB of archives.
> After this operation, 271 kB of additional disk space will be used.
> Err:1 http://ports.ubuntu.com/ubuntu-ports jammy-updates/main arm64 libudev-dev arm64 249.11-0ubuntu3.10
>   404  Not Found [IP: 185.125.190.39 80]
> E: Failed to fetch http://ports.ubuntu.com/ubuntu-ports/pool/main/s/systemd/libudev-dev_249.11-0ubuntu3.10_arm64.deb  404  Not Found [IP: 185.125.190.39 80]
> E: Unable to fetch some archives, maybe run apt-get update or try with --fix-missing?

See https://github.com/probe-rs/probe-rs/actions/runs/8425489394/job/23071714150#step:8:466

This is on a buildjet runner (buildjet-2vcpu-ubuntu-2204-arm), with cargo-dist v0.12.

Manually running `sudo apt-get update` before the dependency install step fixes this, but it would be great if cargo-dist could do that automatically.

### Additional contract requirements

- For generated GitHub Actions output that installs `musl-tools`, the `packages_install` value must be exactly `sudo apt-get update && sudo apt-get install musl-tools`.
