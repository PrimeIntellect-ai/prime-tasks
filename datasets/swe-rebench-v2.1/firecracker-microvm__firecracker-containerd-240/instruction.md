Cannot reuse a Firecracker VM from multiple containers without specifying Container Count
(From #225)

Probably due to the way we handle stub drives, re-using a Firecracker VM from multiple containers doesn't work due to a mysterious

> Drive "root_drive" could not be found

error.

### Additional contract requirements

When a Firecracker VM is configured, the final VM configuration's `Drives` slice must contain one stub drive per container, with at least one stub drive even when the container count is zero or unspecified, in addition to the root drive. Each stub drive must have a unique `DriveID` of the form `stub0`, `stub1`, ..., a `PathOnHost` supplied by the stub-drive handler, `IsReadOnly` set to false, and `IsRootDevice` set to false. The stub drives must appear first in the `Drives` slice, in `stub0`, `stub1`, ... order, before the root drive.

The stub-drive handler's `PatchStubDrive` operation replaces a stub drive with the drive of a container being created. It must replace only stub drives: it must never replace the root drive or any other non-stub drive, and once every stub drive has been replaced, further calls must fail instead of replacing a non-stub drive.


- The handler must replace stub drives in `stub0`, `stub1`, ... order.
- If a call fails after all stub drives have been replaced, the returned drive ID must not be `root_drive`.
