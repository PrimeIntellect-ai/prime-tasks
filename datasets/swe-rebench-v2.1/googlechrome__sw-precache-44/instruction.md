Defining a directory that doesn't exist
If you attempt to write to a path that doesn't exist at the time its run, swPrecache.write throws:

Error: ENOENT: no such file or directory, open '<Directory>/service-worker.js'

### Additional contract requirements

- When the destination's parent directory does not exist, `swPrecache.write` must create it and successfully write the generated file.
