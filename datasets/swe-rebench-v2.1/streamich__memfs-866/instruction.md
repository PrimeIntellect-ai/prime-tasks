"utimes" doesn't work for directories: "EISDIR: illegal operation on a directory, open ..." error
`utimes` [HIDDEN] obviously throws `EISDIR` error.

https://github.com/streamich/memfs/blob/674a1e78469e1e9e766db7e3160538e958fdd97b/src/volume.ts#L1771-L1778

### Additional contract requirements

- Directory support: `utimes` must succeed for a directory and set its access and modification times to the supplied values.
