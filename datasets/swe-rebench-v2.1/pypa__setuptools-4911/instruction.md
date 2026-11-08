[BUG] Version 78.0.1 breaks install of ansible-vault package
### setuptools version

78.0.1

### Python version

3.11

### OS

Ubuntu

### Additional environment information

_No response_

### Description

When installing the "ansible-vault" package, setuptools raises this exception:
```

$ pip install ansible-vault --upgrade
Collecting ansible-vault
  Using cached ansible-vault-2.1.0.tar.gz (3.5 kB)
  Installing build dependencies ... done
  Getting requirements to build wheel ... error
  error: subprocess-exited-with-error

  × Getting requirements to build wheel did not run successfully.
  │ exit code: 1
  ╰─> [34 lines of output]
      Traceback (most recent call last):
        File "/Users/maiera/virtualenvs/vpcauto311/lib/python3.11/site-packages/pip/_vendor/pyproject_hooks/_in_process/_in_process.py", line 389, in <module>
          main()
        File "/Users/maiera/virtualenvs/vpcauto311/lib/python3.11/site-packages/pip/_vendor/pyproject_hooks/_in_process/_in_process.py", line 373, in main
          json_out["return_val"] = hook(**hook_input["kwargs"])
                                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
        File "/Users/maiera/virtualenvs/vpcauto311/lib/python3.11/site-packages/pip/_vendor/pyproject_hooks/_in_process/_in_process.py", line 143, in get_requires_for_build_wheel
          return hook(config_settings)
                 ^^^^^^^^^^^^^^^^^^^^^
        File "/private/var/folders/tg/fy7jbcg96lv1_hvlmcv263kr0000gn/T/pip-build-env-1hnvit19/overlay/lib/python3.11/site-packages/setuptools/build_meta.py", line 334, in get_requires_for_build_wheel
          return self._get_build_requires(config_settings, requirements=[])
                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
        File "/private/var/folders/tg/fy7jbcg96lv1_hvlmcv263kr0000gn/T/pip-build-env-1hnvit19/overlay/lib/python3.11/site-packages/setuptools/build_meta.py", line 304, in _get_build_requires
          self.run_setup()
        File "/private/var/folders/tg/fy7jbcg96lv1_hvlmcv263kr0000gn/T/pip-build-env-1hnvit19/overlay/lib/python3.11/site-packages/setuptools/build_meta.py", line 522, in run_setup
          super().run_setup(setup_script=setup_script)
        File "/private/var/folders/tg/fy7jbcg96lv1_hvlmcv263kr0000gn/T/pip-build-env-1hnvit19/overlay/lib/python3.11/site-packages/setuptools/build_meta.py", line 320, in run_setup
          exec(code, locals())
        File "<string>", line 11, in <module>
        File "/private/var/folders/tg/fy7jbcg96lv1_hvlmcv263kr0000gn/T/pip-build-env-1hnvit19/overlay/lib/python3.11/site-packages/setuptools/__init__.py", line 116, in setup
          _install_setup_requires(attrs)
        File "/private/var/folders/tg/fy7jbcg96lv1_hvlmcv263kr0000gn/T/pip-build-env-1hnvit19/overlay/lib/python3.11/site-packages/setuptools/__init__.py", line 87, in _install_setup_requires
          dist.parse_config_files(ignore_option_errors=True)
        File "/Users/maiera/virtualenvs/vpcauto311/lib/python3.11/site-packages/_virtualenv.py", line 22, in parse_config_files
          result = old_parse_config_files(self, *args, **kwargs)
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
        File "/private/var/folders/tg/fy7jbcg96lv1_hvlmcv263kr0000gn/T/pip-build-env-1hnvit19/overlay/lib/python3.11/site-packages/setuptools/dist.py", line 730, in parse_config_files
          self._parse_config_files(filenames=inifiles)
        File "/private/var/folders/tg/fy7jbcg96lv1_hvlmcv263kr0000gn/T/pip-build-env-1hnvit19/overlay/lib/python3.11/site-packages/setuptools/dist.py", line 599, in _parse_config_files
          opt = self._enforce_underscore(opt, section)
                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
        File "/private/var/folders/tg/fy7jbcg96lv1_hvlmcv263kr0000gn/T/pip-build-env-1hnvit19/overlay/lib/python3.11/site-packages/setuptools/dist.py", line 629, in _enforce_underscore
          raise InvalidConfigError(
      setuptools.errors.InvalidConfigError: Invalid dash-separated key 'description-file' in 'metadata' (setup.cfg), please use the underscore name 'description_file' instead.
      [end of output]

  note: This error originates from a subprocess, and is likely not a problem with pip.
error: subprocess-exited-with-error

× Getting requirements to build wheel did not run successfully.
│ exit code: 1
╰─> See above for output.

note: This error originates from a subprocess, and is likely not a problem with pip.
```

### Expected behavior

ansible-vault has not changed since 2021 and should install as before.

### How to Reproduce

1. Create and activate a fresh Pyhton virtual env, using Python 3.11:
```
mkvirtualenv test -p python3.11
```
2. Install version 78.0.1 of setuptools
```
pip install setuptools==78.0.1
```
3. Install ansible-vault
```
pip install ansible-vault
```

### Output

See above
