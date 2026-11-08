TypeError when using a record array to plot data
<!-- In the following, please describe your issue in detail! -->
<!-- If some sections do not apply, just remove them. -->

### Short description
<!-- This should summarize the issue. -->
Using a NumPy record array as data to plot results in the following:
`TypeError: Cannot compare structured or void to non-void arrays.`

### Code to reproduce
<!-- Please provide a minimal working example that reproduces the issue in the code block below.
     Ideally, this should be a full example someone else could run without additional setup. -->

```python
import pyqtgraph as pg
import numpy as np

data_array = np.recarray((10,), dtype=[('x', float), ('y', float)])
pg.plot(data_array)

pg.exec()
```

### Expected behavior
<!-- What should happen? -->
According to the API reference, a PlotDataItem can be initialized with a NumPy recarray with `dtype=[('x', float), ('y', float), ...]`, so the above code should plot the (uninitialized) recarray data.

### Real behavior
<!-- What happens? -->
```
Traceback (most recent call last):
  File "C:\Users\_\code\recarray_test.py", line 5, in <module>
    pg.plot(data_array)
  File "C:\Users\_\code\.venv\lib\site-packages\pyqtgraph\__init__.py", line 392, in plot
    w.plot(*args, **dataArgs)
  File "C:\Users\_\code\.venv\lib\site-packages\pyqtgraph\graphicsItems\PlotItem\PlotItem.py", line 630, in plot
    item = PlotDataItem(*args, **kargs)
  File "C:\Users\_\code\.venv\lib\site-packages\pyqtgraph\graphicsItems\PlotDataItem.py", line 375, in __init__
    self.setData(*args, **kargs)
  File "C:\Users\_\code\.venv\lib\site-packages\pyqtgraph\graphicsItems\PlotDataItem.py", line 719, in setData
    if 'x' in data:
TypeError: Cannot compare structured or void to non-void arrays.
```

### Tested environment(s)

 * PyQtGraph version: 0.13.7
 * Qt Python binding: PyQt6 6.8.1 Qt 6.8.2
 * Python version: 3.9.13
 * NumPy version: 2.0.2
 * Operating system: Windows 11
 * Installation method: pip
