"µm" is not recognized as a unit symbol
* unyt version: v1.0.4
* Python version: Python 3.6.4
* Operating System: macOS High Sierra 10.13.6 (17G65)

### Description

I was trying to convert meters to microns using the unicode symbol "µ", but the library failed to convert it (see the error below), though it works with `um`.
**What you expected to happen:** conversion is done successfully!

### What I Did

```py
$ ipython
Python 3.6.4 |Anaconda, Inc.| (default, Mar 12 2018, 20:05:31)
Type 'copyright', 'credits' or 'license' for more information
IPython 6.2.1 -- An enhanced Interactive Python. Type '?' for help.

In [1]: import unyt as u

In [2]: d = 1 * u.m

In [3]: d
Out[3]: unyt_quantity(1., 'm')

In [4]: d.to('um')
Out[4]: unyt_quantity(1000000., 'um')

In [5]: d.to('µm')
---------------------------------------------------------------------------
UnitParseError                            Traceback (most recent call last)
<ipython-input-5-7faeac57c1a5> in <module>()
----> 1 d.to('µm')

~/anaconda3/envs/sirepo_bluesky/lib/python3.6/site-packages/unyt/array.py in to(self, units, equivalence, **kwargs)
    828         898755178736817.6 J
    829         """
--> 830         return self.in_units(units, equivalence=equivalence, **kwargs)
    831
    832     def to_value(self, units=None, equivalence=None, **kwargs):

~/anaconda3/envs/sirepo_bluesky/lib/python3.6/site-packages/unyt/array.py in in_units(self, units, equivalence, **kwargs)
    760         898755178736817.6 J
    761         """
--> 762         units = _sanitize_units_convert(units, self.units.registry)
    763         if equivalence is None:
    764             try:

~/anaconda3/envs/sirepo_bluesky/lib/python3.6/site-packages/unyt/array.py in _sanitize_units_convert(possible_units, registry)
    254
    255     # let Unit() try to parse this if it's not already a Unit
--> 256     unit = Unit(possible_units, registry=registry)
    257
    258     return unit

~/anaconda3/envs/sirepo_bluesky/lib/python3.6/site-packages/unyt/unit_object.py in __new__(cls, unit_expr, base_value, base_offset, dimensions, registry, latex_repr)
    301         else:
    302             # lookup the unit symbols
--> 303             unit_data = _get_unit_data_from_expr(unit_expr, registry.lut)
    304             base_value = unit_data[0]
    305             dimensions = unit_data[1]

~/anaconda3/envs/sirepo_bluesky/lib/python3.6/site-packages/unyt/unit_object.py in _get_unit_data_from_expr(unit_expr, unit_symbol_lut)
    862
    863     if isinstance(unit_expr, Symbol):
--> 864         return _lookup_unit_symbol(str(unit_expr), unit_symbol_lut)
    865
    866     if isinstance(unit_expr, Pow):

~/anaconda3/envs/sirepo_bluesky/lib/python3.6/site-packages/unyt/unit_object.py in _lookup_unit_symbol(symbol_str, unit_symbol_lut)
    962     else:
    963         raise UnitParseError("Could not find unit symbol '%s' in the provided "
--> 964                              "symbols." % symbol_str)
    965
    966

UnitParseError: Could not find unit symbol 'µm' in the provided symbols.

In [6]:
```
