[BUG] Package cannot be noarch if scripts argument is used
**Describe the bug**
A clear and concise description of what the bug is.

If a package has the `scripts` argument in _setup.py_ it cannot be [`noarch`](https://conda-forge.org/docs/maintainer/knowledge_base.html#noarch-python). Currently, this is not taken into account by Grayskull.

**To Reproduce**
Steps to reproduce the behavior:
1. Create package

**Expected behavior**
A clear and concise description of what you expected to happen.

`noarch: python` should not be included in the `build:` section.

**Outputs**
If applicable, add the output to help explain your problem.

One example is [`remove_dagmc_tags`](https://github.com/svalinn/remove_dagmc_tags) which has the following [_setup.py_](https://github.com/svalinn/remove_dagmc_tags/blob/c529c688959647faaebba0a932f96c0c10891f61/setup.py#L17)

```python
setuptools.setup(
    name="remove_dagmc_tags",
    version="0.0.5",
    author="DAGMC development team",
    description="A tool for selectively removing tags such as the graveyard from DAGMC h5m files.",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/svalinn/remove_dagmc_tags",
    packages=setuptools.find_packages(),
    zip_safe=True,
    package_dir={"remove_dagmc_tags": "remove_dagmc_tags"},
    scripts=['remove_dagmc_tags/remove-dagmc-tags'],
    package_data={
        "remove_dagmc_tags": [
            "requirements.txt",
            "README.md",
            "LICENSE",
        ],
        "tests": [
            "dagmc.h5m"
        ]
    },
    install_requires=[
        "numpy"
    ],
    # pymoab is also required for this package but is not available via pip
    # install
    tests_require=["pytest-cov"],
)
```

The output here is

```yaml
build:
  number: 0
  noarch: python
  script: {{ PYTHON }} -m pip install . -vv
```

**Environment:**
 - https://www.marcelotrevisani.com/grayskull

**Additional context**
Add any other context about the problem here.
