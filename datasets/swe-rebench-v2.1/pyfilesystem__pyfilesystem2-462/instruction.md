FTPFS should use MDTM
Regarding fs.ftpfs.FS.getinfo (https://github.com/PyFilesystem/pyfilesystem2/blob/64d7a52e1f3037f33937f91e9db812cafdbbafc0/fs/ftpfs.py#L648)

That function tries to use MLST to retrieve arbitrary information of a single file and defaults to LIST if MLST is not supported.
This makes `fs.copy_dir_if_newer` incredibly inefficient on systems that do not support MLST.

Imo, an easy solution would be to possibly support MDTM as a fallback if only the modified datetime is requested, e.g. if `namespace == ("detail", "modified")`.
Another, probably more complex improvement, would be to cache the LIST response rather than call it for every single file.

I can submit a PR for the first suggestion, if I get the okay that this is something that should be included. Possibly also the second, although I'm not sure yet how to best implement that.

### Additional contract requirements

When an FTP resource's modified timestamp is needed without other file information, retrieve it with MDTM when the server advertises support, rather than requiring full-information retrieval. If MDTM is unavailable, ordinary information retrieval must remain available as a fallback. Directory-copy comparisons that only need modification times should use this mtime-only retrieval behavior.
