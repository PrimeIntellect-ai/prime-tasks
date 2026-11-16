Allow specifying command-line parameters in `noxfile`
Related #133, #40, #135.

Noxfiles should be able to specify *some* of the command-line args in the noxfile, for example:

```python
import nox

nox.options.envdir = ".cache"
nox.options.sessions = ["tests", "lint"]

...
```

Command-line args should *override* these "defaults" in the noxfile.
