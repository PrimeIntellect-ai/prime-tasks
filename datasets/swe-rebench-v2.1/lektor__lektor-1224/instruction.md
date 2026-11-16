Bug: `build_url` may remove trailing slash
Found this by browsing through the source. Havent tested whether this is actually an issue, but:

https://github.com/lektor/lektor/blob/dbae91e9c767093349b122f62e114e32e8291f85/lektor/utils.py#L666-L668

[HIDDEN]

Otherwise, an URL like this `/path.my/page/2/` may wrongly remove the trailing slash.

### Additional contract requirements

- A dot in an earlier path component must not cause `build_url` to omit the trailing slash from a directory-style URL.
