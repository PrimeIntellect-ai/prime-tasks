Bug: assertion tripped when auditing a URL-style requirement without egg marker
I noticed this while root-causing #349.

The following:

```bash
pip-audit -r <(echo 'git+https://github.com/unbit/uwsgi.git@1bb9ad77c6d2d310c2d6d1d9ad62de61f725b824')
```

fails with:

```
Traceback (most recent call last):
  File "/Users/william/devel/pip-audit/env/bin/pip-audit", line 8, in <module>
    sys.exit(audit())
  File "/Users/william/devel/pip-audit/pip_audit/_cli.py", line 432, in audit
    for (spec, vulns) in auditor.audit(source):
  File "/Users/william/devel/pip-audit/pip_audit/_audit.py", line 66, in audit
    for dep, vulns in self._service.query_all(specs):
  File "/Users/william/devel/pip-audit/pip_audit/_service/interface.py", line 150, in query_all
    for spec in specs:
  File "/Users/william/devel/pip-audit/pip_audit/_dependency_source/requirement.py", line 104, in collect
    assert isinstance(req, EditableRequirement)
AssertionError
```

...which is:

```python
for req in rf.requirements:
    if req.req is None:
        # For editable requirements that don't have an egg fragment that lists the
        # the package name and version, `pip-requirements-parser` won't attach a
        # `Requirement` object to the `InstallRequirement`.
        #
        # In this case, we can't audit the dependency so we should signal to the
        # caller that we're skipping it.
        [HIDDEN]
```

[HIDDEN] we should support URL requirements that aren't marked as editable.

CC @tetsuo-cpp for thoughts, since I think this was your change.

### Additional contract requirements

- When a URL-style requirement has no egg marker and its package/specifier pair cannot be deduced, report it as skipped rather than failing. Preserve the original requirement line as the skipped item’s name and explain that an egg fragment such as `#egg=your_package_name==your_package_version` can be supplied.
