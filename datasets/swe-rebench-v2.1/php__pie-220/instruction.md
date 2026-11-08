Add support for installing from path
For testing purposes it would be great if I could install a local extension without having to go over the registry.

e.g `pie install --path .`

### Additional contract requirements

- Running `pie install` with no package argument (for example `pie install --path .`) must delegate to the `install-extensions-for-project` sub-command, which installs the local extension from the current working directory.
