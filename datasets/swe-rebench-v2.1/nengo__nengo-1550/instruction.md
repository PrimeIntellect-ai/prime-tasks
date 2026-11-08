SpikingRectifiedLinear does not cache decoders
**Describe the bug**

`SpikingRectifiedLinear` does not cache decoders.

**To reproduce**

A minimal code snippet to reproduce the behavior:

```python
import nengo
from nengo.cache import Fingerprint

print(Fingerprint.supports(nengo.neurons.SpikingRectifiedLinear()))
print(Fingerprint.supports(nengo.neurons.RectifiedLinear()))
```

**Expected behavior**

```
True
True
```

**Error message and logs**

```
False
True
```

**Versions**

 - OS: N/A
 - Python: N/A
 - Nengo: latest master
 - Other: N/A

**Additional context**

May need a better process for keeping these things in sync when new models / etc are added. Have not gone through to check for others that could be missing from the whitelist.
