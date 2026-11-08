Allow building inside a container
It would be nice if mkosi could be launched inside a container to build an image.

### Additional contract requirements

Add a command line option `--nspawn-keep-unit`. When it is enabled, the
systemd-nspawn invocations mkosi performs while building an image must use the
current unit scope by passing `--keep-unit` to systemd-nspawn, so that mkosi can
be run from inside a container or a service unit. When the option is not enabled,
mkosi must not pass `--keep-unit`.
