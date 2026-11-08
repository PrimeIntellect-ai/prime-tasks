Add support for 'nextfile'
https://www.gnu.org/software/gawk/manual/html_node/Nextfile-Statement.html

This is not in the current POSIX spec, but onetrueawk, Gawk, mawk, and busybox awk all support it (and [apparently](https://unix.stackexchange.com/questions/588906/is-awks-nextfile-specified-in-posix) it was [accepted](https://www.austingroupbugs.net/view.php?id=607) into POSIX years ago, but the spec hasn't been updated yet).

### Additional contract requirements

- When `nextfile` appears inside `BEGIN` or `END`, report the exact diagnostic text `nextfile can't be inside BEGIN or END`.
