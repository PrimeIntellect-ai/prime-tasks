`dist.dependencies.apt` config is ignored when using `cargo-xwin`
## Reproduction

dist-workspace.toml:
```
[dist]
targets = ["x86_64-unknown-linux-gnu", "aarch64-pc-windows-msvc"]

[dist.dependencies.apt]
libllvm18 = '*'
```

## Observations

The plan section for `x86_64-unknown-linux-gnu` contains (as expected):
```
"packages_install": "sudo apt-get update\nsudo apt-get install libllvm18\nif ! command -v cargo-zigbuild > /dev/null 2>&1; then\n  if ! command -v pip3 > /dev/null 2>&1; then\n    dnf install --assumeyes python3-pip\n    pip3 install --upgrade pip\n  fi\n  pip3 install cargo-zigbuild\nfi"
```

The plan section for `aarch64-pc-windows-msvc` contains (missing dependencies):
```
"packages_install": "if ! command -v cargo-xwin > /dev/null 2>&1; then\n  if ! command -v pip3 > /dev/null 2>&1; then\n    dnf install --assumeyes python3-pip\n    pip3 install --upgrade pip\n  fi\n  pip3 install cargo-xwin\nfi",
```

### Additional contract requirements

- Configured `dist.dependencies.apt` packages must be included in the generated
  CI plan's installation behavior for a target built with `cargo-xwin`.
- In the generated CI plan, the container configuration for a target built with
  `cargo-xwin` must declare `package_manager` as `apt`.
