Scan not robust to corrupted file
## Description

@jinwar and his student collected a dataset which has a corrupted file. When attempting to read the time array in this file h5py raises an error stating the metadata checksum is bad. When trying to index this directory with `spool.update` the error bubbles to the surface and crashes the indexing.  This is because `dascore.scan` is not robust to files which have their file format correctly identified but then raise an error when attempting to read them.

Although the presence of a corrupted file is certainly not something we can control, DASCore should be robust to this, issue a warning, then skip the problematic file and move on with indexing. This may be a bit tricky to test as the corrupted file is too large to include in the test suite. So, we could either:

1. Muck about with the bytes of a small test file until we can produce this same error, or
2. Create a test in which we monkey patch one of the formatter scan functions to raise an error if a specific file is given


## Example
-- Can't currently reproduce with a self contained code snippet.

## Versions
 - OS [e.g. Ubuntu 20.04]: CentOS
 - DasCore Version [e.g. 0.0.5]: 0.1.0
 - Python Version [e.g. 3.10]: 3.11

### Additional contract requirements

- Emit a `UserWarning` whose message contains `Failed to scan`.
