Support complete version specification syntax for CMake and ninja versions
Currently scikit-build-core supports specifying [minimum required CMake and ninja versions](https://scikit-build-core.readthedocs.io/en/latest/configuration.html#cmake-and-ninja-minimum-versions) in pyproject.toml. While this may be sufficient most of the time, sometimes more precise version requests are necessary. It would be good for scikit-build-core to support full version specs here.

### Additional contract requirements

The `cmake.version` and `ninja.version` settings accept complete PEP 440 version specifier expressions, including exclusion operators, and use them to determine whether an installed tool version is acceptable. The existing `cmake.minimum-version` and `ninja.minimum-version` settings remain supported as lower-bound requirements for backward compatibility.
