Error when probing neurons with advanced indexing
**Describe the bug**

Probing a subset of some neurons using advanced indexing results in an error.

The issue is that we changed neuron probes from "connection probes" to "signal probes", and you can't do advanced indexing directly on a signal. [HIDDEN]

**To reproduce**

A minimal code snippet to reproduce the behavior:

```python
import nengo

with nengo.Network() as net:
    ens = nengo.Ensemble(10, 1)
    nengo.Probe(ens.neurons[[1, 3]])

with nengo.Simulator(net) as sim:
    pass
```

**Expected behavior**

There should be no error, the indicated neurons should be probed.

**Error message and logs**

```
  ...
  File "...\nengo\builder\probe.py", line 117, in build_probe
    signal_probe(model, key, probe)
  File "...\nengo\builder\probe.py", line 57, in signal_probe
    sig = sig[probe.slice]
  File "...\nengo\builder\signal.py", line 150, in __getitem__
    raise SignalError("Can only index or slice into signals")
nengo.exceptions.SignalError: Can only index or slice into signals
```

**Versions**

 - OS: Windows 10
 - Python: 3.8
 - Nengo: master

### Additional contract requirements

A neuron probe using advanced indexing must record the selected neurons without raising an error.
