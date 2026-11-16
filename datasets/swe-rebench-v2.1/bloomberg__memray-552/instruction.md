`memray run` overwrites `sys.argv[0]` even when `-I` or `-P` is used
`memray run` tries to match the updates to `sys.path` that are performed by the interpreter itself when it starts. When those path updates are suppressed (by the `-I` or `-P` command line flags or their corresponding environment variables), Memray's emulation winds up overwriting paths in `sys.path` that needed to be left alone.

### Additional contract requirements

The affected behavior is Memray's emulation of interpreter updates to `sys.path`, not an update to `sys.argv[0]`. If Python suppresses a relevant `sys.path` update because of `-I`, `-P`, or `PYTHONSAFEPATH`, `memray run` must preserve the interpreter-provided paths and must not add the path that the suppressed startup update would have inserted. When startup does perform a relevant update, `memray run` must continue to emulate it.
