Add support for python_implementation
We currently support `platform.python_implementation` and `platform_python_implementation`. `setuptools`' previous fork of packaging did support `python_implementation` until it was replaced by `platform_python_implementation` in <https://github.com/pypa/setuptools/commit/3bd5118eaa87b4f6598e0a473fec3623b6579d3b#diff-0c04a5cfcbd2a4bdd1121db108b79d3d>.

`python_implementation` existed in `setuptools` until that commit and the death of `MarkerEvaluation`, see <https://github.com/pypa/setuptools/blob/f8b1293c408bbb652bec3f2ae6e5b4f33f3ca55e/pkg_resources/__init__.py#L1389> for the full (?) list of what was supported there. It also briefly existed in PEP 508 until February (<https://hg.python.org/peps/rev/655a101719a5> replaced it with `platform_python_implementation`).

The one thing we're missing from what `setuptools` historically supported is `python_implementation`; we have everything else. This adds more duplication, but its removal broke some packages (e.g., some versions of html5lib).
