package json digest dict mapped to simple json hashes dict causes pip >23 to fail
blake2b_256 has been added to the digest dict in package json, pip does not know how to handle this hash name. Causing and exception when trying to install packages with pip23 or later.

If you check https://pypi.org/simple/pip against https://pypi.org/simple/pip/23.0.1/json
the digest dict does not contain the same data as the hashes dict.

```
$ pip install --force pip
Looking in indexes: https://<pypi mirror>/simple/
Collecting pip
  Using cached https://<pypi mirror>/packages/07/51/2c0959c5adf988c44d9e1e0d940f5b074516ecc87e96b1af25f59de9ba38/pip-23.0.1-py3-none-any.whl (2.1 MB)
ERROR: Unknown hash name: blake2b_256
```

This is caused by how bandersnatch discovers the hashes that should be applied to /simple/
https://github.com/pypa/bandersnatch/blob/f99542f17adcc5c35ddfbb62b03a84d43122793a/src/bandersnatch/simple.py#L192
```
def generate_json_simple_page(
        ...
        # Add release files into the JSON dict
        for r in release_files:
            package_json["files"].append(
                {
                    "filename": r["filename"],
[HIDDEN]
                    "requires-python": r.get("requires_python", ""),
                    "url": self._file_url_to_local_url(r["url"]),
                    "yanked": r.get("yanked", False),
                }
            )
```

### Additional contract requirements

For each file in generated simple JSON, the `hashes` mapping must contain only the digest name and digest value selected by the mirror's `digest_name` setting for that file in the corresponding simple HTML representation. It must not include other package digest names, including names that pip does not recognize.
