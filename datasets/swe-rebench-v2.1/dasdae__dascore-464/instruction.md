slope_filter with units
## Description
The `filt` parameter of `slope_filter` doesn't appear to handle units.

## Example
```python
import dascore as dc

patch = dc.get_example_patch()
speed = 5_000 * dc.get_quantity("m/s")

filt = [speed * .90, speed*.95, speed*1.05, speed*1.1]
out = patch.slope_filter(filt)  # raises dimensionality error.
```

## Expected behavior
This should work. Moreover, it should be able to determine which dimensions to apply the filter to (as long as multiple dimensions don't have the same units).

## Versions
 - OS [e.g. Ubuntu 20.04]:
 - DasCore Version [e.g. 0.0.5]:
 - Python Version [e.g. 3.10]:
