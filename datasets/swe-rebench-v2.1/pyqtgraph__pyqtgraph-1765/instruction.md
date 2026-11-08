Plot option `maxTraces` is doing the opposite of what it's supposed to do
### Short description
`maxTraces` plot option is hiding the most recent `n` lines, rather than only showing them.

### Code to reproduce
```python
import pyqtgraph as pg
import numpy as np

p = pg.plot()
p.plotItem.ctrl.maxTracesCheck.setChecked(True)
p.plotItem.ctrl.maxTracesSpin.setValue(3)

for i in range(10):
    p.plot(np.random.normal(size=100) + i*10)
```

### Expected behavior
The plot should only show the 3 top-most lines.

### Real behavior
The plot shows only the 7 bottom-most lines.

### Tested environment(s)

 * PyQtGraph version: master
 * Qt Python binding: PyQt5 5.12.3
 * Python version: 3.7.10
 * NumPy version: 1.20.2
 * Operating system: linux, windows
 * Installation method: conda + git

### Additional Context
This behavior is the same when the option is controlled through the plot's menu interface. Hopefully I'll get around to fixing this presently.

### Additional contract requirements

When the `maxTraces` limit is disabled, traces hidden solely because of that limit become visible again.
