Incorrect shebang in .git/hooks/pre-commit for python3 only installations
The shebang for `.git/hooks/pre-commit` is `#!/usr/bin/env python`. I work with setups where `python3` is the only python in env.

Could the shebang be the install python instead? I.e. the installation under `INSTALL_PYTHON = '/usr/bin/python3'`
