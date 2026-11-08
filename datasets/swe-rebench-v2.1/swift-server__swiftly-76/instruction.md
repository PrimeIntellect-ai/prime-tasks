Provide option to use the newly installed toolchain
The `install` command should accept an argument (e.g. `--use`) which will automatically use the new toolchain if installation succeeds. This already happens by default if there are no toolchains installed yet, but this would be very useful in other cases too.

### Additional contract requirements

When a toolchain is already active, installing another toolchain without the opt-in argument must leave the active toolchain unchanged. If no toolchain is active, a successful first installation must activate the installed toolchain by default. The install command's opt-in argument must make the newly installed toolchain active on success, even when another toolchain was active beforehand.
