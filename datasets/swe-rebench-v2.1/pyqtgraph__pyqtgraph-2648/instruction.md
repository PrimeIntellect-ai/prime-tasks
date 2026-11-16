ColorMap.getByIndex() returns wrong colors
<!-- In the following, please describe your issue in detail! -->
<!-- If some sections do not apply, just remove them. -->

### Short description
<!-- This should summarize the issue. -->
ColorMap.getByIndex() returns wrong colors.

### Code to reproduce
<!-- Please provide a minimal working example that reproduces the issue in the code block below.
     Ideally, this should be a full example someone else could run without additional setup. -->

```python
In [1]: import pyqtgraph as pg
In [2]: cm = pg.ColorMap([0.0, 1.0], [(0,0,0), (255,0,0)])
In [3]: cm.getByIndex(0)
Out[3]: PySide6.QtGui.QColor.fromRgbF(0.000000, 0.000000, 0.000000, 0.003922)
In [4]: cm.getByIndex(1)
Out[4]: PySide6.QtGui.QColor.fromRgbF(0.003922, 0.000000, 0.000000, 0.003922)
```

### Tested environment(s)

 * PyQtGraph version: 0.13.2.dev0
