Bug in APE-14 description of WCS
I'm running into issues with a solar GWCS where the high-level objects are astropy coordinates with default values of arcseconds. To reproduce this you will need the following dataset:

https://github.com/astropy/reproject/blob/main/reproject/tests/data/aia_171_level1.asdf

The issue:

```python
In [1]: import asdf

In [3]: aia = asdf.open("/Users/tom/Code/Astropy/reproject/reproject/tests/data/aia_171_level1.asdf")

In [5]: aia['wcs'].world_axis_object_components
Out[5]: [('celestial', 0, 'spherical.lon'), ('celestial', 1, 'spherical.lat')]

In [7]: aia['wcs'].world_axis_units
Out[7]: ('deg', 'deg')

In [8]: coord = aia['wcs'].pixel_to_world(1, 2)

In [9]: coord.spherical.lon
Out[9]: <Longitude -1203.0967792 arcsec>
```

Basically the issue is that ``world_axis_object_components`` is incorrect because if applied to the high level objects, it will not give values that could be passed directly to ``world_to_pixel_values`` (which it should). I *think* the following would be more correct:

```python
In [5]: aia['wcs'].world_axis_object_components
Out[5]: [('celestial', 0, 'spherical.lon.deg'), ('celestial', 1, 'spherical.lat.deg')]
```

Is this an issue in GWCS, or in the ASDF file? (I don't understand where all the layers live).
