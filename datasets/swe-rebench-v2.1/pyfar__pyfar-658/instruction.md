Filtering `Signal` alters its `cshape`
## General

* pyfar version: 0.6.6
* Python version: 3.10.12
* Operating System: Ubuntu LTS 22.04.4
* Did you install pyfar via pip: yes

## Description
Filtering a `Signal` changes its `cshape`, if one dimension is `1`. I don't want my shapes being touched. Worse, it leads to incorrect broadcasting down the line.

## What I Did

MWE
``` python
#!/usr/bin/env python3

import numpy as np
import pyfar


sig = pyfar.Signal(np.zeros((4,1,10)), 1)
out = pyfar.dsp.filter.butterworth(sig, 2, 0.1)

print(sig)
print(out)
print(sig-out)
```
Output
``` bash
time domain energy Signal:
(4, 1) channels with 10 samples @ 1 Hz sampling rate and none FFT normalization

time domain energy Signal:
(4,) channels with 10 samples @ 1 Hz sampling rate and none FFT normalization

freq domain energy Signal:
(4, 4) channels with 10 samples @ 1 Hz sampling rate and none FFT normalization
```
