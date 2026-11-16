Some builtins not properly placed on non-standard Python installations (conda)
Consider this file:

``` python
import thirdparty
import os
import ftplib
import ABC
import numbers
import colorama
```

On Windows with a **conda** Python 2.7 installation, `isort` produces this:

``` python
import os

import colorama

import ABC
import ftplib
import numbers
import thirdparty
```

(Note that `ftplib` and `numbers` were incorrectly placed in the "third party" section).

[HIDDEN]

Standard python is installed by default in `C:\Python27` or `C:\Python34` which explains why the above works in general, but in systems which have Python from anaconda or even Python installed in a non-standard location that logic does not work and the library is considered "thirdparty".

My Python is installed at `E:\Miniconda\python.exe` , so here's the path to `ftplib`:

```
$ python -c "import ftplib;print(ftplib.__file__)"
E:\Miniconda\lib\ftplib.pyc
```

A workaround is to add those builtin files in the `known_standard_library` config options.

### Additional contract requirements

Modules from Python's standard library must remain in the standard-library section when Python is installed at a non-standard location, including paths that do not contain a Python-version directory name. A differently cased import must not be classified as a standard-library import solely because the host filesystem resolves the case-insensitive path.
