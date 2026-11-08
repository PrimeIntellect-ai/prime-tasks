io.write(..., compress=True) increases file size
## General

* pyfar version: 0.6.9
* Python version: 3.11.9
* Operating System: Ubuntu 23.10
* Did you install pyfar via pip: yes

## Description
Hi guys,

I noticed that instead of compressing the data, `pf.io.write()` produces much bigger files when using `compress=True`.

I tested this with a sine signal. The behavior is consistent for long and short signals and single-channel as well as multi-channel audio.

When using noise, the difference decreases but the compressed file is still larger than the uncompressed one.

## What I Did

```
import pyfar as pf

signal = pf.signals.sine(frequency=1000, n_samples=44100, amplitude=1, sampling_rate=44100)

pf.io.write('signal_uncompressed', signal=signal)
pf.io.write('signal_compressed', signal=signal, compress=True)
```
`signal_uncompressed.far` is 383.4 kB, while `signal_compressed.far` is 706.7 kB.
