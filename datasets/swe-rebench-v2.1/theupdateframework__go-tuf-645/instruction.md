I increase the default `MaxRootRotations` value for the updater config.
The current default value is 32, which is quite small. For some scenarios where the repository is large, a refresh from the first root.json may fail.
Note that clients *should* cache the metadata, to avoid large number of rotations which is inefficient, and clients *should* embed a "fresh" version of the root to avoid unnecessary rotations, but in some scenarios it's unavoidable, such as when verifying the complete chain of root files.

### Additional contract requirements

- Set the default `MaxRootRotations` value to 256.
