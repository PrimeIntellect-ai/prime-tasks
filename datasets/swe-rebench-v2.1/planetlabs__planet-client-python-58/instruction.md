atomic file support
when downloading files, ensure files are written atomically

### Additional contract requirements

For a download written to a filesystem path, the complete downloaded contents become visible only after the download succeeds. If a download fails, an existing destination retains its previous contents, and a destination that did not previously exist is not left behind.
