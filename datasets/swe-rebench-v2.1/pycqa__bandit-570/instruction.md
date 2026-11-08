general_bad_file_permissions permits most dangerous flag
The logic in `general_bad_file_permissions` seems to ignore `stat.S_IXOTH` (execute by others), which is the most dangerous of all the POSIX file flags.

It raises a high severity issue for `S_IWOTH` (write by others) and it raises a medium severity issue for `S_IXGRP` (execute by group).

The following test raises no issues:

```python
import os
import stat

os.chmod('/path/to/binary/i/just/uploaded', stat.S_IXOTH)
```

The guide referenced in the file documents why it is bad to have this flag:
https://security.openstack.org/guidelines/dg_apply-restrictive-file-permissions.html#testing-guide

### Additional contract requirements

- An `os.chmod` call setting `stat.S_IXOTH` (the execute-by-others bit, mode value `0o001`) must raise a MEDIUM-severity issue.
- An `os.chmod` call setting `stat.S_IWGRP` (the group-writable bit, mode value `0o020`) must raise a MEDIUM-severity issue.
- Issues raised by this check are reported with HIGH confidence.
