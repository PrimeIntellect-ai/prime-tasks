tilde in dependency no longer parsing
### Checklist

- [x] I added a descriptive title
- [x] I searched open reports and couldn't find a duplicate

### What happened?

I have an environment.yml file that uses `~=` in the pip key. With conda-lock 2 this parsed without error, but version 3 produces the following error

```python
[ins] In [1]: import conda_lock

[ins] In [2]: conda_lock.__version__
Out[2]: '3.0.0'

[ins] In [3]: from conda_lock.src_parser.pyproject_toml import poetry_version_to_conda_version

[ins] In [4]: poetry_version_to_conda_version('~=1.36')
---------------------------------------------------------------------------
InvalidVersion                            Traceback (most recent call last)
Cell In[4], line 1
----> 1 poetry_version_to_conda_version('~=1.36')

File ~/Applications/miniconda3/lib/python3.12/site-packages/conda_lock/src_parser/pyproject_toml.py:108, in poetry_version_to_conda_version(version_string)
    106 if version_string is None:
    107     return None
--> 108 conda_version = encode_poetry_version(version_string)
    109 # Python's '===' is explicitly discouraged in PEP 440:
    110 # <https://peps.python.org/pep-0440/#arbitrary-equality>
    111 # Python's '==' seems equivalent to conda's '==':
    112 # <https://peps.python.org/pep-0440/#version-matching>
    113 # <https://docs.conda.io/projects/conda-build/en/latest/resources/package-spec.html#id4>
    114 conda_version = conda_version.replace("===", "==")

File ~/Applications/miniconda3/lib/python3.12/site-packages/conda_lock/_vendor/grayskull/strategy/parse_poetry_version.py:215, in encode_poetry_version(poetry_specifier)
    [HIDDEN]
--> 215     floor = coerce_to_semver(target)
    216     ceiling = get_tilde_ceiling(target)
    217     conda_clauses.append(">=" + floor)

File ~/Applications/miniconda3/lib/python3.12/site-packages/conda_lock/_vendor/grayskull/strategy/parse_poetry_version.py:64, in coerce_to_semver(version)
     61 if semver.VersionInfo.is_valid(version):
     62     return version
---> 64 parsed_version = parse_version(version)
     65 vinfo = vdict_to_vinfo(parsed_version)
     66 return str(vinfo)

File ~/Applications/miniconda3/lib/python3.12/site-packages/conda_lock/_vendor/grayskull/strategy/parse_poetry_version.py:40, in parse_version(version)
     38 match = VERSION_REGEX.search(version)
     39 if not match:
---> 40     raise InvalidVersion(f"Could not parse version {version}.")
     42 return {
     43     key: None if value is None else int(value)
     44     for key, value in match.groupdict().items()
     45 }

InvalidVersion: Could not parse version =1.36.
```

### Additional Context

Here's the result from version 2

```python
[ins] In [4]: import conda_lock

[ins] In [5]: conda_lock.__version__
Out[5]: '2.5.6'

[ins] In [6]: from conda_lock.src_parser.pyproject_toml import poetry_version_to_conda_version

[ins] In [7]: poetry_version_to_conda_version('~=1.36')
Out[7]: '>=1.36,<1.37'
```

### Additional contract requirements

- The converter must accept a compatible-release specifier such as `~=1.36` without raising `InvalidVersion`.
