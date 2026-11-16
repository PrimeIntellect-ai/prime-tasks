Can't install Version 1.2.4 - No module named 'public'
**System:** CentOS 7
**Python Version:** 3.6 (from Software Collection)
**PIP Version:** 21.0.1
**Virtualenv:** yes

**Description:**

When I try to install version 1.2.4 from pypi, the install will be discarded and version 1.2.2 is insalled instead.

The reason is, that the module atpuplic is not installed. So the error "ModuleNotFoundError: No module named 'public'" is raised.


**Stacktrace:**

```
(testenv) [root@78e76264529c /]# pip install -i https://pypi.org/simple aiosmtpd
Collecting aiosmtpd
  Downloading aiosmtpd-1.2.4.tar.gz (83 kB)
     |################################| 83 kB 340 kB/s
  Installing build dependencies ... done
  Getting requirements to build wheel ... error
  ERROR: Command errored out with exit status 1:
   command: /testenv/bin/python /testenv/lib64/python3.6/site-packages/pip/_vendor/pep517/_in_process.py get_requires_for_build_wheel /tmp/tmpxbr7mohf
       cwd: /tmp/pip-install-s4res86q/aiosmtpd_1b7979a5651c4ef48a1f5c635ab706a8
  Complete output (55 lines):
  Traceback (most recent call last):
    File "/tmp/pip-build-env-1ki9o5ff/overlay/lib/python3.6/site-packages/setuptools/config.py", line 387, in _parse_attr
      return getattr(StaticModule(module_name), attr_name)
    File "/tmp/pip-build-env-1ki9o5ff/overlay/lib/python3.6/site-packages/setuptools/config.py", line 26, in __init__
      src = strm.read()
    File "/opt/rh/rh-python36/root/usr/lib64/python3.6/encodings/ascii.py", line 26, in decode
      return codecs.ascii_decode(input, self.errors)[0]
  UnicodeDecodeError: 'ascii' codec can't decode byte 0xc2 in position 30439: ordinal not in range(128)

  During handling of the above exception, another exception occurred:

  Traceback (most recent call last):
    File "/testenv/lib64/python3.6/site-packages/pip/_vendor/pep517/_in_process.py", line 280, in <module>
      main()
    File "/testenv/lib64/python3.6/site-packages/pip/_vendor/pep517/_in_process.py", line 263, in main
      json_out['return_val'] = hook(**hook_input['kwargs'])
    File "/testenv/lib64/python3.6/site-packages/pip/_vendor/pep517/_in_process.py", line 114, in get_requires_for_build_wheel
      return hook(config_settings)
    File "/tmp/pip-build-env-1ki9o5ff/overlay/lib/python3.6/site-packages/setuptools/build_meta.py", line 150, in get_requires_for_build_wheel
      config_settings, requirements=['wheel'])
    File "/tmp/pip-build-env-1ki9o5ff/overlay/lib/python3.6/site-packages/setuptools/build_meta.py", line 130, in _get_build_requires
      self.run_setup()
    File "/tmp/pip-build-env-1ki9o5ff/overlay/lib/python3.6/site-packages/setuptools/build_meta.py", line 145, in run_setup
      exec(compile(code, __file__, 'exec'), locals())
    File "setup.py", line 4, in <module>
      setup()
    File "/tmp/pip-build-env-1ki9o5ff/overlay/lib/python3.6/site-packages/setuptools/__init__.py", line 153, in setup
      return distutils.core.setup(**attrs)
    File "/opt/rh/rh-python36/root/usr/lib64/python3.6/distutils/core.py", line 121, in setup
      dist.parse_config_files()
    File "/tmp/pip-build-env-1ki9o5ff/overlay/lib/python3.6/site-packages/setuptools/dist.py", line 681, in parse_config_files
      ignore_option_errors=ignore_option_errors)
    File "/tmp/pip-build-env-1ki9o5ff/overlay/lib/python3.6/site-packages/setuptools/config.py", line 157, in parse_configuration
      meta.parse()
    File "/tmp/pip-build-env-1ki9o5ff/overlay/lib/python3.6/site-packages/setuptools/config.py", line 463, in parse
      section_parser_method(section_options)
    File "/tmp/pip-build-env-1ki9o5ff/overlay/lib/python3.6/site-packages/setuptools/config.py", line 436, in parse_section
      self[name] = value
    File "/tmp/pip-build-env-1ki9o5ff/overlay/lib/python3.6/site-packages/setuptools/config.py", line 220, in __setitem__
      value = parser(value)
    File "/tmp/pip-build-env-1ki9o5ff/overlay/lib/python3.6/site-packages/setuptools/config.py", line 552, in _parse_version
      version = self._parse_attr(value, self.package_dir)
    File "/tmp/pip-build-env-1ki9o5ff/overlay/lib/python3.6/site-packages/setuptools/config.py", line 390, in _parse_attr
      module = importlib.import_module(module_name)
    File "/opt/rh/rh-python36/root/usr/lib64/python3.6/importlib/__init__.py", line 126, in import_module
      return _bootstrap._gcd_import(name[level:], package, level)
    File "<frozen importlib._bootstrap>", line 994, in _gcd_import
    File "<frozen importlib._bootstrap>", line 971, in _find_and_load
    File "<frozen importlib._bootstrap>", line 955, in _find_and_load_unlocked
    File "<frozen importlib._bootstrap>", line 665, in _load_unlocked
    File "<frozen importlib._bootstrap_external>", line 678, in exec_module
    File "<frozen importlib._bootstrap>", line 219, in _call_with_frames_removed
    File "/tmp/pip-install-s4res86q/aiosmtpd_1b7979a5651c4ef48a1f5c635ab706a8/aiosmtpd/smtp.py", line 15, in <module>
      from public import public
  ModuleNotFoundError: No module named 'public'
  ----------------------------------------
WARNING: Discarding https://files.pythonhosted.org/packages/68/00/736583da7ce52b0ff3e8ce9045d2c1a183d1877a59a4362be50f49e49b03/aiosmtpd-1.2.4.tar.gz#sha256=34cea0ecd0495f752e1c4bfe5f541676d7aab29674390c007834a63fe7ba0bda (from https://pypi.org/simple/aiosmtpd/) (requires-python:~=3.6). Command errored out with exit status 1: /testenv/bin/python /testenv/lib64/python3.6/site-packages/pip/_vendor/pep517/_in_process.py get_requires_for_build_wheel /tmp/tmpxbr7mohf Check the logs for full command output.
  Downloading aiosmtpd-1.2.2.tar.gz (170 kB)
     |################################| 170 kB 12.4 MB/s
Collecting atpublic
  Downloading atpublic-2.1.2.tar.gz (16 kB)
Collecting typing_extensions
  Downloading typing_extensions-3.7.4.3-py3-none-any.whl (22 kB)
Using legacy 'setup.py install' for aiosmtpd, since package 'wheel' is not installed.
Using legacy 'setup.py install' for atpublic, since package 'wheel' is not installed.
Installing collected packages: typing-extensions, atpublic, aiosmtpd
    Running setup.py install for atpublic ... done
    Running setup.py install for aiosmtpd ... done
Successfully installed aiosmtpd-1.2.2 atpublic-2.1.2 typing-extensions-3.7.4.3
```
