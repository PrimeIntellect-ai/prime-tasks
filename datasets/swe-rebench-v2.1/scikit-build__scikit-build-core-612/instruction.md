Wheel build tag support
Hello,

According to the https://peps.python.org/pep-0491/ the wheel name may include {build tag}, which is useful when the wheel packaging is part of CI, do you have a plans to support it?

The wheel filename is {distribution}-{version}(**-{build tag}**)?-{python tag}-{abi tag}-{platform tag}.whl.

Thanks,
Mikhail

### Additional contract requirements

- When a wheel build is given a build tag, the built wheel's filename must include it directly after the distribution name and version and before the Python, ABI, and platform tags, e.g. `cmake_example-0.0.1-1foo-<python>-<abi>-<platform>.whl`.
- The build tag is supplied through the `wheel.build-tag` setting, which can be given in `pyproject.toml` under `[tool.scikit-build]` (for example `wheel.build-tag = "1foo"`) or as a config setting (`wheel.build-tag` or `skbuild.wheel.build-tag`).
