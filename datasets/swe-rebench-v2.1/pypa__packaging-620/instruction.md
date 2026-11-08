Spaces in platform names are problematic
On some platforms, `sysconfig.get_platform()` returns a value with a space in it (e.g. `isilon onefs`).
This causes problems for wheel building/handling.

First, there is an issue trying to build a platform-specific wheel:
``` console
# venv/bin/pip install -I --no-cache pyyaml
Collecting pyyaml
  Downloading PyYAML-6.0.tar.gz (124 kB)
     ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 125.0/125.0 KB 13.3 MB/s eta 0:00:00
  Installing build dependencies ... done
  Getting requirements to build wheel ... done
  Preparing metadata (pyproject.toml) ... done
Building wheels for collected packages: pyyaml
  Building wheel for pyyaml (pyproject.toml) ... error
  error: subprocess-exited-with-error

  × Building wheel for pyyaml (pyproject.toml) did not run successfully.
  │ exit code: 1
  ╰─> [101 lines of output]
...
      wheel.cli.WheelError: Bad wheel filename 'PyYAML-6.0-cp38-cp38-isilon onefs_9_5_0_0_amd64.whl'
      [end of output]

  note: This error originates from a subprocess, and is likely not a problem with pip.
  ERROR: Failed building wheel for pyyaml
```
I created https://github.com/pypa/wheel/pull/491 to address this.

Even with that patch in place, though, `pip` is unable to install the built wheel because `packaging` does not recognize that the platform name has had its spaces replaced with underscores:
``` console
# python3 -m pip install dist/PyYAML-6.0-cp38-cp38-isilon_onefs_9_5_0_0_amd64.whl
...
ERROR: PyYAML-6.0-cp38-cp38-isilon_onefs_9_5_0_0_amd64.whl is not a supported wheel on this platform.
```
