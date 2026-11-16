FakeOsModule.walk return a (Path, list, list) generator instead of a (str, list, list) when a pathlib object is used as input
**Describe the bug**
method FakeOsModule.walk of <pyfakefs.fake_os.FakeOsModule> is returning a Path object as first element instead of a string as the os.walk method do.

**How To Reproduce**
```python
from pathlib import Path

# Real os part
import os
os_output = list(os.walk(Path(os.getcwd())))  # Deepest element is a tuple of [str, list, list]
# Example ("C:\\", [], [])

# Fake os part
from pyfakefs import fake_filesystem, fake_os
filesystem = fake_filesystem.FakeFilesystem()
os_module = fake_os.FakeOsModule(filesystem)
fs_output = list(os_module.walk(Path(os_module.getcwd())))  # Deepest element is a tuple of [WindowsPath, list, list]
# Example (WindowsPath(C:\), list, list)
fs_output_str = list(os_module.walk(os_module.getcwd()))  # Deepest element is a tuple of [str, list, list] like os.walk
# Example ("C:\\", [], [])

# Warning as walk will return a tuple if there is no subdirectory or a list of tuple otherwise
assert type(os_output[0][...][0]) is type(fs_output[0])  # Adapt the element to look at the first element of one of the deepest tuples
```

**Your environment**
platform.platform: Windows-10-10.0.22621-SP0
sys.version: Python 3.11.6 (tags/v3.11.6:8b6ee5b, Oct  2 2023, 14:57:12) [MSC v.1935 64 bit (AMD64)]
pyfakefs: 5.3.1
pytest: 7.4.3
