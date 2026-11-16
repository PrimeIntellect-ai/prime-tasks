Spool.chunk does not count samples correctly
## Description
<!--
Provide a clear description of the issue.
-->

The code below raises an error because the chunk function is one sample short. Related to #356.

```python
import dascore as dc
from dascore.utils.time import to_float


spool = dc.get_example_spool()
pa_merged = spool.chunk(time=None)[0]

# the spool has 24.0 seconds of data
pa_merged_length = pa_merged.coords.coord_range("time")

# but chunk with kwarg 24.0 raises error as it expects kwarg <= time_max-time_min which is 23.996
pa_merged = spool.chunk(time=to_float(pa_merged_length))
```

## Example
<!--
Include a short example that reproduces the issue, if applicable.
-->

## Expected behavior
<!--
Describe the expected behavior, if applicable.
-->

## Versions
 - OS [e.g. Ubuntu 20.04]:
 - DasCore Version [e.g. 0.0.5]:
 - Python Version [e.g. 3.10]:
