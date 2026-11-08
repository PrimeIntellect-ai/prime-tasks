sbd data is not exported if devices in SBD_DEVICE have an space after ;
sbd data is not exported if devices in SBD_DEVICE have an space after `;`.

This setup works for sbd.

Here an example (check the space after the `;`):
```
SBD_DEVICE="/dev/disk/by-id/scsi-SLIO-ORG_IBLOCK_8071fac5-f560-4c78-b1fb-77ca7c86ebd5; /dev/disk/by-id/scsi-SLIO-ORG_IBLOCK_7eab20b6-1755-400a-8a41-d191dfe2e09b"
```

We would need to [HIDDEN] to catch this scenario too, as it is allowed by sbd

### Additional contract requirements

- Parse and export SBD_DEVICE entries separated by a semicolon even when a space follows the semicolon.
