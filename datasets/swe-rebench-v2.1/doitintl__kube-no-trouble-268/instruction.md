Add a version command
Hi,

would it be possible to add a `kubent --version` or `kubent version` command to check the current version?

I'd like to use that command to verify that the installation was correctly. Currently, when running `kubent version` it'll start `kubent` without any error or waning :D

### Additional contract requirements

The version command must report the current version in its output, exit with status 0, and return without starting the normal kubent scan.
