[BUG] grayskull separates multiple licenses with `&` rather than `AND`
**Describe the bug**
A clear and concise description of what the bug is.

**To Reproduce**
`grayskull pypi marshmallow`
resulting `marshmallow/meta.yaml` has a line `  license: MIT & BSD-3-Clause` that produces:
```
Hi! This is the friendly automated conda-forge-linting service.

I just wanted to let you know that I linted all conda-recipes in your PR (recipe) and found it was in an excellent condition.

I do have some suggestions for making it better though...

For recipe:

License is not an SPDX identifier (or a custom LicenseRef) nor an SPDX license expression.
Documentation on acceptable licenses can be found [here](https://conda-forge.org/docs/maintainer/adding_pkgs.html#spdx-identifiers-and-expressions).
```
from conda-forge's linter.

See: https://github.com/conda-forge/marshmallow-feedstock/pull/64

**Expected behavior**
`  license: MIT AND BSD-3-Clause`, which makes conda-forge's linter happy:
```
Hi! This is the friendly automated conda-forge-linting service.

I just wanted to let you know that I linted all conda-recipes in your PR (recipe) and found it was in an excellent condition.
```

See also: https://conda-forge.org/docs/maintainer/adding_pkgs.html#spdx-identifiers-and-expressions

**Environment:**
 - `grayskull --version`: 1.8.4
