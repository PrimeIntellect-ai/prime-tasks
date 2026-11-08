[feature] Meson Tool support specific args like '--strip' when install()
### What is your suggestion?

From meson 0.62, meson install support '--strip', but there are no way to pass it to conan's tools.Meson.
> --tags TAGS                           Install only targets having one of the
                                        given tags. (Since 0.60.0)
  --strip                               Strip targets even if strip option was
                                        not set during configure. (Since 0.62.0)

May be a conf like for cmake:
> tools.cmake:install_strip: Add --strip to cmake.install()

### Have you read the CONTRIBUTING guide?

- [x] I've read the CONTRIBUTING guide

### Additional contract requirements

- The Meson tool's install operation must support Meson's `--strip` option, controlled by the boolean configuration `tools.build:install_strip`.
- When `tools.build:install_strip` is set to `True`, running the Meson tool's install operation must include `--strip` in the install command.
- When `tools.build:install_strip` is not set, or is set to `False`, the install command must not include `--strip`.
