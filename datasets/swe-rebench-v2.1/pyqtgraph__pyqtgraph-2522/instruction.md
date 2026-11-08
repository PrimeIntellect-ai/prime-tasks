`QMenu`s not destroyed (memory leak)
I found, that when you repeatedly instantiate `PlotItem`s and delete them again, the corresponding `QMenu` objects for the context menus of the plots never get destroyed. I saw lot's of `QMenu` instances using GammaRay (https://www.kdab.com/development-resources/qt-tools/gammaray/)

But this can simply be reproduced with the following snippet. The more often you create, add and remove new plot instances the more memory is used. Simply increase `N` to e.g. 100, 500, 1000, 2000 and check the memory usage.

```
import pyqtgraph as pg

app = pg.mkQApp()
widget = pg.GraphicsLayoutWidget()
widget.show()

N = 10
for i in range(N):
    plot = pg.PlotItem()
    plot.plot(x=[0,i, N], y=[0.0, 1.0, 0.0])
    widget.addItem(plot)
    app.processEvents()
    widget.removeItem(plot)

if __name__ == '__main__':
    pg.exec()
```

### Additional contract requirements

- Repeatedly creating plots, adding and removing them from a layout, and discarding them must not leave their context menus or submenus alive.
- The plot's context menu is exposed by `PlotItem.getMenu()`. When a plot is
  closed (`PlotItem.close()`, as invoked by `PlotWidget.close()`), that menu and
  every submenu reachable from it must be destroyed rather than kept alive;
  `pyqtgraph.Qt.isQObjectAlive` must report them as no longer alive.
