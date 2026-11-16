[Bug]: aqt 3.2.1 fails under python 3.9
### Bug description

When running aqt version 3.2.1 under python 3.9, it gives this error message:
```
Traceback (most recent call last):
  File "/Users/francis/gitlab/builds/iqwiKzxd/0/kuvacode/smartshooter6/out/venv/bin/aqt", line 5, in <module>
    from aqt.__main__ import main
  File "/Users/francis/gitlab/builds/iqwiKzxd/0/kuvacode/smartshooter6/out/venv/lib/python3.9/site-packages/aqt/__init__.py", line 30, in <module>
    from aqt.installer import Cli
  File "/Users/francis/gitlab/builds/iqwiKzxd/0/kuvacode/smartshooter6/out/venv/lib/python3.9/site-packages/aqt/installer.py", line 45, in <module>
    from aqt.archives import QtArchives, QtPackage, SrcDocExamplesArchives, ToolArchives
  File "/Users/francis/gitlab/builds/iqwiKzxd/0/kuvacode/smartshooter6/out/venv/lib/python3.9/site-packages/aqt/archives.py", line 32, in <module>
    from aqt.helper import Settings, get_hash, getUrl, ssplit
  File "/Users/francis/gitlab/builds/iqwiKzxd/0/kuvacode/smartshooter6/out/venv/lib/python3.9/site-packages/aqt/helper.py", line 650, in <module>
    def extract_auth(args: List[str]) -> Tuple[str | None, str | None, List[str] | None]:
TypeError: unsupported operand type(s) for |: 'type' and 'NoneType'
```

Python 3.9 is the current version present on macOS Sonoma, so it would be nice to fix this.
Reverting back to aqt 3.2.0 solves the issue.

### Expected behavior

Not to trigger python exception.

### aqt and python version

aqt v3.2.1 on python v3.9.6

### Operating System

MacOS

### Relevant log output

```shell
Traceback (most recent call last):
  File "/Users/francis/gitlab/builds/iqwiKzxd/0/kuvacode/smartshooter6/out/venv/bin/aqt", line 5, in <module>
    from aqt.__main__ import main
  File "/Users/francis/gitlab/builds/iqwiKzxd/0/kuvacode/smartshooter6/out/venv/lib/python3.9/site-packages/aqt/__init__.py", line 30, in <module>
    from aqt.installer import Cli
  File "/Users/francis/gitlab/builds/iqwiKzxd/0/kuvacode/smartshooter6/out/venv/lib/python3.9/site-packages/aqt/installer.py", line 45, in <module>
    from aqt.archives import QtArchives, QtPackage, SrcDocExamplesArchives, ToolArchives
  File "/Users/francis/gitlab/builds/iqwiKzxd/0/kuvacode/smartshooter6/out/venv/lib/python3.9/site-packages/aqt/archives.py", line 32, in <module>
    from aqt.helper import Settings, get_hash, getUrl, ssplit
  File "/Users/francis/gitlab/builds/iqwiKzxd/0/kuvacode/smartshooter6/out/venv/lib/python3.9/site-packages/aqt/helper.py", line 650, in <module>
    def extract_auth(args: List[str]) -> Tuple[str | None, str | None, List[str] | None]:
TypeError: unsupported operand type(s) for |: 'type' and 'NoneType'
```

### Code of Conduct

- [x] I agree to follow this project's Code of Conduct
