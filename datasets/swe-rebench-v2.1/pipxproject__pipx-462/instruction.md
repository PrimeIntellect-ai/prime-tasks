Installing VCS URL should not use `--editable` option
<!-- Thank you for filing a bug! Please feel free to answer as much or as little of this template as you can. -->

**Describe the bug**
<!-- Please be as detailed as possible! -->
Our package name detection scheme depends on installing a package first with pip and querying its name.  pip seems to allow installation with a bare VCS url **ONLY** if the `--editable` flag is not present.  If the `--editable` flag is present, then pip seems to require the suffix `#egg=<package_name>`.

**How to reproduce**
<!-- If possible, include output of `pipx --verbose ...` -->

Using a git package from another issue I was reading (#148) and trying to reproduce:

```
birchtree:pipx pipx install --verbose --editable git+https://github.com/raxod502/diary-manager
pipx > (run_subprocess:112): running /usr/local/opt/python@3.8/bin/python3.8 -m venv --without-pip /var/folders/gp/7z0mcw717y1b0kt0swc1lfp80000gn/T/tmp_5cntfli
pipx > (run_subprocess:112): running /var/folders/gp/7z0mcw717y1b0kt0swc1lfp80000gn/T/tmp_5cntfli/bin/python -c import sysconfig; print(sysconfig.get_path('purelib'))
pipx > (run_subprocess:112): running /Users/mclapp/.local/pipx/shared/bin/python -c import sysconfig; print(sysconfig.get_path('purelib'))
pipx > (run_subprocess:112): running /var/folders/gp/7z0mcw717y1b0kt0swc1lfp80000gn/T/tmp_5cntfli/bin/python --version
pipx > (run_subprocess:112): running /var/folders/gp/7z0mcw717y1b0kt0swc1lfp80000gn/T/tmp_5cntfli/bin/python -m pip list --format=json
pipx > (run_subprocess:112): running /var/folders/gp/7z0mcw717y1b0kt0swc1lfp80000gn/T/tmp_5cntfli/bin/python -m pip install --no-dependencies --editable git+https://github.com/raxod502/diary-manager
ERROR: Could not detect requirement name for 'git+https://github.com/raxod502/diary-manager', please specify one with #egg=your_package_name
pipx > (install_package_no_deps:221): '/var/folders/gp/7z0mcw717y1b0kt0swc1lfp80000gn/T/tmp_5cntfli/bin/python -m pip install --no-dependencies --editable git+https://github.com/raxod502/diary-manager' failed
Cannot determine package name from spec 'git+https://github.com/raxod502/diary-manager'. Check package spec for errors.
```

Just with pip itself, `--editable` + VCS URL needs `#egg`:
```
birchtree:pipx pip install --no-dependencies --editable git+https://github.com/raxod502/diary-manager
ERROR: Could not detect requirement name for 'git+https://github.com/raxod502/diary-manager', please specify one with #egg=your_package_name
```
Just with pip itself, bare VCS URL does NOT need `#egg`:
```
birchtree:pipx pip install --no-dependencies git+https://github.com/raxod502/diary-manager
Collecting git+https://github.com/raxod502/diary-manager
  Cloning https://github.com/raxod502/diary-manager to /private/var/folders/gp/7z0mcw717y1b0kt0swc1lfp80000gn/T/pip-req-build-5kt0mjb7
  Running command git clone -q https://github.com/raxod502/diary-manager /private/var/folders/gp/7z0mcw717y1b0kt0swc1lfp80000gn/T/pip-req-build-5kt0mjb7
Using legacy setup.py install for diary-manager, since package 'wheel' is not installed.
Installing collected packages: diary-manager
    Running setup.py install for diary-manager ... done
Successfully installed diary-manager-2.0.2
```

**Expected behavior**
<!-- What should have happened? -->
I expected pip could install the VCS URL whether it was --editable or not.
