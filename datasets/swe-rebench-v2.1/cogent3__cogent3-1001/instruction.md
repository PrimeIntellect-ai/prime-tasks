load_tree doesn't cope with pathlib.Path
```python
import pathlib
from cogent3 import load_tree

path = pathlib.Path("~/repos/Cogent3/tests/data")
tree = load_tree(path / "murphy.tree")
```
generates
```
AttributeError                            Traceback (most recent call last)
/var/folders/rh/t24zj19s7qxd4_4p0n5rqjy00000gn/T/ipykernel_9969/1104250210.py in <module>
      3
      4 path = pathlib.Path("~/repos/Cogent3/tests/data")
----> 5 tree = load_tree(path / "murphy.tree")

~/opt/miniconda3/envs/c39dev/lib/python3.9/site-packages/cogent3/__init__.py in load_tree(filename, format, underscore_unmunge)
    594     with open_(filename) as tfile:
    595         treestring = tfile.read()
--> 596         if format is None and filename.endswith(".xml"):
    597             format = "xml"
    598

AttributeError: 'PosixPath' object has no attribute 'endswith'
```
