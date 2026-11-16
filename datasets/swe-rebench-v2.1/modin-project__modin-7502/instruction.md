allow I/O function overrides
We do this wrapping in general.py: https://github.com/modin-project/modin/blob/33e2377e786c1a60adc84a945d53ccbbd6068c3b/modin/pandas/general.py#L43

But we should do it for I/O methods too.
