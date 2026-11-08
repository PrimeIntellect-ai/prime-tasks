Support `--disable-gil` builds (PEP 703) in packaging.tags
The `packaging.tags` requires two changes to support the experimental `--disable-gil` builds:

1. The `packaging.tags._cpython_abis()` function should return "t" in the ABI for `--disable-gil` builds
2. The `packaging.tags.cpython_tags()` function should exclude "abi3" for `--disable-gil` builds. There is [ongoing discussion](https://discuss.python.org/t/python-abis-and-pep-703/34018/55) on how to support features from the stable ABI, but that's more likely to take the form of an "abi4".
