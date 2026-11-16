Update OrderedSet?
The [oset package](https://anaconda.org/conda-forge/oset) has not been updated in a while... (2 years 9 months!) Also the repository link is broken--the repo is gone? For these reasons, it might be nice to switch to a different package:
https://github.com/simonpercivall/orderedset, https://anaconda.org/conda-forge/orderedset - BSD-3, last upload 3 months ago
https://github.com/LuminosoInsight/ordered-set, https://anaconda.org/conda-forge/ordered-set - MIT, last upload 10 months ago

another benefit of these is we can more easily contribute to the code (raise issues, submit PRs, etc.)

edit: and we may need to update this soon anyway
```
python3.7/site-packages/oset/pyoset.py:16: DeprecationWarning: Using or importing the ABCs from 'collections' instead of from 'collections.abc' is deprecated since Python 3.3,and in 3.9 it will stop working
```

### Additional contract requirements

The replacement for the stale ordered-set dependency must preserve the insertion order of Compound children while supporting membership checks and adding and removing children. Installing mBuild must not require the `oset` package. Importing mBuild must not emit the deprecated `collections` ABC warning described above.
