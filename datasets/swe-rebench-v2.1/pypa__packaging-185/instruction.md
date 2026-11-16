packaging.tags does not include `m` for abi tag in Python 3.7 (and below)
**Environment**

**OS**: Windows 10
**Packaging version**: 19.1
**Python version**: `Python 3.7.4 (tags/v3.7.4:e09359112e, Jul  8 2019, 20:34:20) [MSC v.1916 64 bit (AMD64)]`, from [nuget](https://www.nuget.org/packages/python)

**Issue**: The ABI tag for Python 3.7 in `sys_tags()` does not have `cp37m` (just `cp37`):

```
(.venv) PS C:\Users\User\Desktop> python -c 'from packaging.tags import sys_tags; print(list(sys_tags()))'
[<cp37-cp37-win_amd64 @ 2675185733256>, <cp37-abi3-win_amd64 @ 2675185848584>, <cp37-none-win_amd64 @ 2675185852360>, <cp36-abi3-win_amd64 @ 2675185868424>, <cp35-abi3-win_amd64 @ 2675185868488>, <cp34-abi3-win_amd64 @ 2675188128520>, <cp33-abi3-win_amd64 @ 2675188128776>, <cp32-abi3-win_amd64 @ 2675188129032>, <py37-none-win_amd64 @ 2675188129544>, <py3-none-win_amd64 @ 2675188154440>, <py36-none-win_amd64 @ 2675188154696>, <py35-none-win_amd64 @ 2675188154952>, <py34-none-win_amd64 @ 2675188155208>, <py33-none-win_amd64 @ 2675188155464>, <py32-none-win_amd64 @ 2675188155720>, <py31-none-win_amd64 @ 2675188155976>, <py30-none-win_amd64 @ 2675188156232>, <cp37-none-any @ 2675188129288>, <py37-none-any @ 2675185733576>, <py3-none-any @ 2675188156680>, <py36-none-any @ 2675188156936>, <py35-none-any @ 2675188157192>, <py34-none-any @ 2675188157448>, <py33-none-any @ 2675188157704>, <py32-none-any @ 2675188157960>, <py31-none-any @ 2675188158216>, <py30-none-any @ 2675188162632>]
```

**Expected**: The ABI tag for Python 3.7 should have `cp37m`.

It looks like we are relying strictly on either `SOABI` or `WITH_PYMALLOC` being available [here](https://github.com/pypa/packaging/blob/9bc25964dce3b4781d5dde7e96e4e9f0d0b6762a/packaging/tags.py#L87-L98), but neither are:

```
(.venv) PS C:\Users\User\Desktop> python -c "from sysconfig import get_config_var as c; print(c('SOABI')); print(c('WITH_PYMALLOC'))"
None
None
```

Related to #180.

### Additional contract requirements

When generating ABI tags for CPython 3.7 and earlier, unavailable `SOABI` and `WITH_PYMALLOC` configuration must not omit the `m` ABI modifier where that modifier applies. In particular, when `sys_tags()` is used for CPython 3.7 with both values unavailable, its tags must include an ABI tag of `cp37m`.
