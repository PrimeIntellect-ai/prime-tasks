pip parses `dist-info-metadata` key from JSON indexes incorrectly
### Description

When using a JSON-based package index, pip expects the `dist-info-metadata` key to always have a string value and does not parse the values described by the spec.

[PEP 691 states](https://peps.python.org/pep-0691/#project-detail):

> `dist-info-metadata`: An optional key that indicates that metadata for this file is available, via the same location as specified in [PEP 658](https://peps.python.org/pep-0658) (`{file_url}.metadata`). **Where this is present, it MUST be either a boolean to indicate if the file has an associated metadata file, or a dictionary mapping hash names to a hex encoded digest of the metadata’s hash.**

pip tries to apply the same string parsing for this value as it does for the `data-dist-info-metadata` value in [PEP 658](https://peps.python.org/pep-0658/#specification) and does not handle booleans or dicts.

This does not work as the entries according to PEP 691 look like:

```json
  {
    "dist-info-metadata": {
      "sha256": "8737b5dbb73f6b05e596c7c659f694a031de98b926e634716d9855fd365a5f2f"
    },
    "filename": "pre_commit-3.3.2-py2.py3-none-any.whl",
    [...]
  },
```

### Expected behavior

pip should handle values with boolean or dict type as described in [PEP 691](https://peps.python.org/pep-0691/#project-detail).

### pip version

Tested with 23.1.2 and current `main`

### Python version

3.11

### OS

Linux (debian bullseye)

### How to Reproduce

To reproduce, we need access to a registry which supports PEP 691 JSON indexes and also PEP 658 metadata.

pypi.org is supposed to support both of these for new file uploads, but there is currently a bug where it provides the metadata under the wrong JSON key (https://github.com/pypi/warehouse/issues/13705), so it is hard to test at the moment. For now, the easiest way to reproduce is to temporarily patch your pip code to use the (incorrect) key to trigger the bug.

1. Temporarily patch your `pip` code so that it uses the key name provided by pypi.org:

    ```diff
    diff --git a/src/pip/_internal/models/link.py b/src/pip/_internal/models/link.py
    index e741c3283..5d1e0be4e 100644
    --- a/src/pip/_internal/models/link.py
    +++ b/src/pip/_internal/models/link.py
    @@ -262,7 +262,7 @@ class Link(KeyBasedCompareMixin):
             url = _ensure_quoted_url(urllib.parse.urljoin(page_url, file_url))
             pyrequire = file_data.get("requires-python")
             yanked_reason = file_data.get("yanked")
    -        dist_info_metadata = file_data.get("dist-info-metadata")
    +        dist_info_metadata = file_data.get("data-dist-info-metadata")
             hashes = file_data.get("hashes", {})

             # The Link.yanked_reason expects an empty string instead of a boolean.
    ```

  2. Try to install a package.

      *  `pip install --no-cache --only-binary :all: pre-commit==3.3.2` to reproduce pip trying to parse a metadata dict as a string
      *  `pip install --no-cache --only-binary :all: pre-commit==3.0.0` to reproduce pip trying to parse a boolean `false` as a string

### Output

```
$ pip install --no-cache --only-binary :all: pre-commit==3.3.2
Collecting pre-commit==3.3.2
ERROR: Exception:
Traceback (most recent call last):
  File "/home/ckuehl/proj/pip/src/pip/_internal/cli/base_command.py", line 169, in exc_logging_wrapper
    status = run_func(*args)
             ^^^^^^^^^^^^^^^
  File "/home/ckuehl/proj/pip/src/pip/_internal/cli/req_command.py", line 248, in wrapper
    return func(self, options, args)
           ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/ckuehl/proj/pip/src/pip/_internal/commands/install.py", line 377, in run
    requirement_set = resolver.resolve(
                      ^^^^^^^^^^^^^^^^^
  File "/home/ckuehl/proj/pip/src/pip/_internal/resolution/resolvelib/resolver.py", line 92, in resolve
    result = self._result = resolver.resolve(
                            ^^^^^^^^^^^^^^^^^
  File "/home/ckuehl/proj/pip/src/pip/_vendor/resolvelib/resolvers.py", line 546, in resolve
    state = resolution.resolve(requirements, max_rounds=max_rounds)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/ckuehl/proj/pip/src/pip/_vendor/resolvelib/resolvers.py", line 397, in resolve
    self._add_to_criteria(self.state.criteria, r, parent=None)
  File "/home/ckuehl/proj/pip/src/pip/_vendor/resolvelib/resolvers.py", line 173, in _add_to_criteria
    if not criterion.candidates:
  File "/home/ckuehl/proj/pip/src/pip/_vendor/resolvelib/structs.py", line 156, in __bool__
    return bool(self._sequence)
           ^^^^^^^^^^^^^^^^^^^^
  File "/home/ckuehl/proj/pip/src/pip/_internal/resolution/resolvelib/found_candidates.py", line 155, in __bool__
    return any(self)
           ^^^^^^^^^
  File "/home/ckuehl/proj/pip/src/pip/_internal/resolution/resolvelib/found_candidates.py", line 143, in <genexpr>
    return (c for c in iterator if id(c) not in self._incompatible_ids)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/ckuehl/proj/pip/src/pip/_internal/resolution/resolvelib/found_candidates.py", line 47, in _iter_built
    candidate = func()
                ^^^^^^
  File "/home/ckuehl/proj/pip/src/pip/_internal/resolution/resolvelib/factory.py", line 206, in _make_candidate_from_link
    self._link_candidate_cache[link] = LinkCandidate(
                                       ^^^^^^^^^^^^^^
  File "/home/ckuehl/proj/pip/src/pip/_internal/resolution/resolvelib/candidates.py", line 293, in __init__
    super().__init__(
  File "/home/ckuehl/proj/pip/src/pip/_internal/resolution/resolvelib/candidates.py", line 156, in __init__
    self.dist = self._prepare()
                ^^^^^^^^^^^^^^^
  File "/home/ckuehl/proj/pip/src/pip/_internal/resolution/resolvelib/candidates.py", line 225, in _prepare
    dist = self._prepare_distribution()
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/ckuehl/proj/pip/src/pip/_internal/resolution/resolvelib/candidates.py", line 304, in _prepare_distribution
    return preparer.prepare_linked_requirement(self._ireq, parallel_builds=True)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/ckuehl/proj/pip/src/pip/_internal/operations/prepare.py", line 510, in prepare_linked_requirement
    metadata_dist = self._fetch_metadata_only(req)
                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/ckuehl/proj/pip/src/pip/_internal/operations/prepare.py", line 374, in _fetch_metadata_only
    return self._fetch_metadata_using_link_data_attr(
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/ckuehl/proj/pip/src/pip/_internal/operations/prepare.py", line 384, in _fetch_metadata_using_link_data_attr
    metadata_link = req.link.metadata_link()
                    ^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/ckuehl/proj/pip/src/pip/_internal/models/link.py", line 417, in metadata_link
    metadata_link_hash = LinkHash.parse_pep658_hash(self.dist_info_metadata)
                         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/ckuehl/proj/pip/src/pip/_internal/models/link.py", line 77, in parse_pep658_hash
    name, sep, value = dist_info_metadata.partition("=")
                       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
AttributeError: 'dict' object has no attribute 'partition'
```

Same traceback for `pre-commit==3.0.0` except the last line is instead

```
AttributeError: 'bool' object has no attribute 'partition'
```

### Code of Conduct

- [X] I agree to follow the [PSF Code of Conduct](https://www.python.org/psf/conduct/).
