Unit conversions with time/length are wrong
* unyt version: 1.0.7
* Python version: 3.6.8
* Operating System: macOS 10.14.2

### Description

When I create quantities with units of `time/length` the unit conversions (e.g., `in_mks` or `in_cgs`) always seem to produce a nonsensical quantity with units of ohms. There is no error or warning produced, just incorrect results.

### What I Did

```
>>> import unyt

# This is to show that units of length/time works fine:
>>> a = unyt.unyt_quantity(100, 'm/s')
>>> a.in_cgs()
unyt_quantity(10000., 'cm/s')

# This is wrong:
>>> b = unyt.unyt_quantity(100, 's/m')
>>> b.in_cgs()
unyt_quantity(8.98755179e+13, 'ohm')
>>> b.in_mks()
unyt_quantity(8.98755179e+13, 'ohm')

# Also:
>>> a.in_cgs().in_cgs()
unyt_quantity(10000., 'cm/s')
>>> b.in_cgs().in_cgs()
unyt_quantity(100., 'statohm')
```
