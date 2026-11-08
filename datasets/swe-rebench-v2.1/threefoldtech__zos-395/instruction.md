provisiond: ZDB provision is broken
```
{
    "level": "error",
    "error": "failed to create 0-db container: failed to create container: OCI runtime create failed: container_linux.go:345: starting container process caused \"process_linux.go:430: container init caused \\\"rootfs_linux.go:58: mounting \\\\\\\"proc\\\\\\\" to rootfs \\\\\\\"/var/cache/modules/flistd/mountpoint/278a0299f935ebc5a1ed219e45e67274bf84c50283bb53e439e6629dd5bc775b\\\\\\\" at \\\\\\\"/proc\\\\\\\" caused \\\\\\\"mkdir /var/cache/modules/flistd/mountpoint/278a0299f935ebc5a1ed219e45e67274bf84c50283bb53e439e6629dd5bc775b/proc: read-only file system\\\\\\\"\\\"\": unknown",
    "time": "2019-11-22T08:00:03Z",
    "message": "failed to provision reservation 97-1"
}
```
I'm suspecting this is because we do a read-only mount of the flist now for ZDB container.

### Additional contract requirements

- When provisioning a ZDB container, mount its flist writable so the container runtime can create `/proc`; provisioning must not fail because the root filesystem is read-only.
