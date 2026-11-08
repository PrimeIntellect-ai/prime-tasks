`tidy-imports --black --width` does not respect specified width (PyInf#11045)
The `tidy-imports --black --width` command does not respect the specified width if the `line-length` is not set in `black`'s configuration in `pyproject.toml`.

Reproducer:
```python
$ vim pyproject.toml
$ cat pyproject.toml  # Empty pyproject.toml

$ vim foo.py
$ cat foo.py
from math import sin,cos,tan,sinh,cosh,tanh,log,floor,log10,remainder,factorial,nextafter,radians
assert [sin,cos,tan,sinh,cosh,tanh,log,floor,log10,remainder,factorial,nextafter,radians]

$ tidy-imports --black --width=100 foo.py
--- /u/bhojwana/tidy-imports-width/foo.py	2025-01-28 15:01:52.214238000 +0530
+++ /tmp/tmpjxbaldh0	2025-01-28 15:02:18.431116451 +0530
@@ -1,2 +1,16 @@
-from math import sin,cos,tan,sinh,cosh,tanh,log,floor,log10,remainder,factorial,nextafter,radians
+from math import (
+    cos,
+    cosh,
+    factorial,
+    floor,
+    log,
+    log10,
+    nextafter,
+    radians,
+    remainder,
+    sin,
+    sinh,
+    tan,
+    tanh,
+)
 assert [sin,cos,tan,sinh,cosh,tanh,log,floor,log10,remainder,factorial,nextafter,radians]

$ tidy-imports --width=200 foo.py
--- /u/bhojwana/tidy-imports-width/foo.py	2025-01-28 15:01:52.214238000 +0530
+++ /tmp/tmpetwjxskj	2025-01-28 15:02:27.929902587 +0530
@@ -1,2 +1,3 @@
-from math import sin,cos,tan,sinh,cosh,tanh,log,floor,log10,remainder,factorial,nextafter,radians
+from   math                     import (cos, cosh, factorial, floor, log, log10, nextafter, radians,
+                                        remainder, sin, sinh, tan, tanh)
 assert [sin,cos,tan,sinh,cosh,tanh,log,floor,log10,remainder,factorial,nextafter,radians]

$ vim pyproject.toml
$ cat pyproject.toml
[tool.black]
line-length = 80

$ tidy-imports --black foo.py
--- /u/bhojwana/tidy-imports-width/foo.py	2025-01-28 15:01:52.214238000 +0530
+++ /tmp/tmpafhd92bp	2025-01-28 15:06:09.183217437 +0530
@@ -1,2 +1,16 @@
-from math import sin,cos,tan,sinh,cosh,tanh,log,floor,log10,remainder,factorial,nextafter,radians
+from math import (
+    cos,
+    cosh,
+    factorial,
+    floor,
+    log,
+    log10,
+    nextafter,
+    radians,
+    remainder,
+    sin,
+    sinh,
+    tan,
+    tanh,
+)
 assert [sin,cos,tan,sinh,cosh,tanh,log,floor,log10,remainder,factorial,nextafter,radians]

$ tidy-imports --black --width=200 foo.py
--- /u/bhojwana/tidy-imports-width/foo.py	2025-01-28 15:01:52.214238000 +0530
+++ /tmp/tmpvho32acv	2025-01-28 15:06:29.396890729 +0530
@@ -1,2 +1,2 @@
-from math import sin,cos,tan,sinh,cosh,tanh,log,floor,log10,remainder,factorial,nextafter,radians
+from math import cos, cosh, factorial, floor, log, log10, nextafter, radians, remainder, sin, sinh, tan, tanh
 assert [sin,cos,tan,sinh,cosh,tanh,log,floor,log10,remainder,factorial,nextafter,radians]
```
**Expected Behavior:**
- `tidy-imports --black --width=<value>` should respect the specified width even if `line-length` is not set in `pyproject.toml`.

**Actual Behavior:**
- `tidy-imports --black --width=<value>` does not respect the specified width if `line-length` is not set in `pyproject.toml`.

**Request:**
- Allow configuring the line length via `--width` even if `line-length` is not specified in `pyproject.toml`.
