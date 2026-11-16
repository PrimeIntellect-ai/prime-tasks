Please add a possibility to configure builder (`cmake --build`) arguments
FWICS there is currently no way to pass additional arguments to the builder, i.e. the equivalent of:

    cmake --build . -- -j12 -l13

Could you please add a configuration knob for that? We really want to respect user job count and load average options in Gentoo.

### Additional contract requirements

The configuration option is `build.tool-args` in the `[tool.scikit-build]` pyproject table. Its string arguments must be forwarded to the CMake build command after the `--` separator, preserving their order.
