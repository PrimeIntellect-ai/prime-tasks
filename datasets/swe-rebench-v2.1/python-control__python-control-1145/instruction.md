Nyquist plot uses incorrect subplot axes
```python3
import control as ctl
import matplotlib.pyplot as plt
P = ctl.tf([1], [2, 1])

fig, ax = plt.subplots(2,2)
ctl.nyquist_plot(P, ax=ax[1,0])
plt.show()
```

The nyquist plot always shows up in the botom right corner, no matter what index into `ax` I use.

When I replace the nyquist with step, it shows up at the correct position (bottom left in this case):
```python3
fig, ax = plt.subplots(2,2)
ctl.step_response(P).plot(ax=ax[1,0])
plt.show()
```

Version: control==0.10.1

### Additional contract requirements

The same supplied-axes handling must be correct for the related plotting
commands that share this code path:

- ``nyquist_plot(..., ax=...)`` must draw the Nyquist curve (lines, markers,
  circles, and text) on the supplied axes.
- ``nichols_plot(..., ax=...)`` must draw the Nichols chart (lines, markers,
  labels, and grid) on the supplied axes.
- ``describing_function_plot(..., ax=...)`` must draw both the Nyquist curve of
  the linear system and the describing function curve (and any intersection
  point labels) on the supplied axes.
- ``step_response(...).plot(ax=...)`` must draw the step response on the
  supplied axes.
