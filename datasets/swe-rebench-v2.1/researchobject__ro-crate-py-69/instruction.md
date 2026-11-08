write_zip should not include the new archive in itself
If one calls `write_zip` with an output path that is within the RO-crate directory, the new zip file ends up inside itself.  As `write_zip` walks the directory tree it'll find the partially written zip file and copy it into the archive.
