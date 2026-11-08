Replace chardet by C version (cchardet)
# Overview

To improve detection speed we better use - https://github.com/PyYoshi/cChardet

### Additional contract requirements

Declare cchardet as a runtime dependency so it is available when the package is installed.
