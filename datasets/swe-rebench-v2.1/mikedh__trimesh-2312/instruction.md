ImportError: cannot import name 'geometry_hash' from 'trimesh.viewer.windowed'
Thanks for a fantastic library. It comes in very useful for me all the time!

I ran into a small bug though. Trying to run the example examples/widget.py I got this error:
`ImportError: cannot import name 'geometry_hash' from 'trimesh.viewer.windowed'`

It seems this function was renamed from `geometry_hash` [HIDDEN] in commit e68432c40261690e08c3388f1453a41cc62bbf61 [HIDDEN]

Changing the widget.py import in my venv site-packages to
```
from .. import rendering
from .trackball import Trackball
from .windowed import SceneViewer
[HIDDEN]
```
fixed the issue for me.

### Additional contract requirements

- Importing the widget viewer used by `examples/widget.py` must succeed; it must not raise an `ImportError` for `geometry_hash` from `trimesh.viewer.windowed`.
