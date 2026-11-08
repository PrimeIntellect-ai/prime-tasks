TypeError in PlotCurveItem.py: arguments did not match any overloaded call
<!-- In the following, please describe your issue in detail! -->
<!-- If some sections do not apply, just remove them. -->

### Short description

With version 0.13.1 in conda, we see a repeated exception in one of our pyqtgraph applications, and the X axis doesn't draw.  It's unclear from the exception if there's a problem with our code or not, the exception appears to be entirely within the pyqtgraph package.

### Expected behavior

X axis draws normally

### Real behavior

```
/home/jrollins/.conda/envs/igwn/lib/python3.9/site-packages/pyqtgraph/debug.py:128: RuntimeWarning: Ignored exception:
Traceback (most recent call last):
  File "/home/jrollins/.conda/envs/igwn/bin/ndscope", line 10, in <module>
    sys.exit(main())
  File "/home/jrollins/.conda/envs/igwn/lib/python3.9/site-packages/ndscope/__main__.py", line 391, in main
    sys.exit(app.exec_())
  File "/home/jrollins/.conda/envs/igwn/lib/python3.9/site-packages/pyqtgraph/widgets/GraphicsView.py", line 137, in paintEvent
    return super().paintEvent(ev)
  File "/home/jrollins/.conda/envs/igwn/lib/python3.9/site-packages/pyqtgraph/debug.py", line 128, in w
    printExc('Ignored exception:')
  --- exception caught here ---
  File "/home/jrollins/.conda/envs/igwn/lib/python3.9/site-packages/pyqtgraph/debug.py", line 126, in w
    func(*args, **kwds)
  File "/home/jrollins/.conda/envs/igwn/lib/python3.9/site-packages/pyqtgraph/graphicsItems/PlotCurveItem.py", line 905, in paint
    p.drawLines(*self._getLineSegments())
TypeError: arguments did not match any overloaded call:
  drawLines(self, PyQt5.sip.array[QLineF]): not enough arguments
  drawLines(self, QLineF, *): not enough arguments
  drawLines(self, PyQt5.sip.array[Union[QPointF, QPoint]]): not enough arguments
  drawLines(self, Union[QPointF, QPoint], *): not enough arguments
  drawLines(self, PyQt5.sip.array[QLine]): not enough arguments
  drawLines(self, QLine, *): not enough arguments
  drawLines(self, PyQt5.sip.array[QPoint]): not enough arguments
  drawLines(self, QPoint, *): not enough arguments
  printExc('Ignored exception:')
```

### Tested environment(s)

 * PyQtGraph version: 0.13.1
 * Qt Python binding: `PyQt5 5.15.7 Qt 5.15.4`
 * Python version: 3.9.13
 * NumPy version: 1.23.3
 * Operating system: linux
 * Installation method: conda

### Additional context
