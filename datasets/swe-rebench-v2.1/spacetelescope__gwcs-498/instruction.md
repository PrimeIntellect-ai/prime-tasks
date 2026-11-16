Bug in treatment of pixel_bounds
Currently if I create a GWCS using the example at the front of the docs:

```python
In [1]: import numpy as np
   ...: from astropy.modeling import models
   ...: from astropy.coordinates import ICRS, SkyCoord
   ...: from astropy import units as u
   ...: from gwcs import wcs
   ...: from gwcs import coordinate_frames as cf
   ...:
   ...: pixelshift = models.Shift(-500) & models.Shift(-500)
   ...: pixelscale = models.Scale(0.1 / 3600.0) & models.Scale(0.1 / 3600.0)  # 0.1 arcsec/pixel
   ...: tangent_projection = models.Pix2Sky_TAN()
   ...: celestial_rotation = models.RotateNative2Celestial(30.0, 45.0, 180.0)
   ...:
   ...: det2sky = pixelshift | pixelscale | tangent_projection | celestial_rotation
   ...:
   ...: detector_frame = cf.Frame2D(name="detector", axes_names=("x", "y"), unit=(u.pix, u.pix))
   ...:
   ...: sky_frame = cf.CelestialFrame(reference_frame=ICRS(), name="icrs", unit=(u.deg, u.deg))
   ...:
   ...: wcsobj = wcs.WCS([(detector_frame, det2sky), (sky_frame, None)])
   ...:
   ...: wcsobj.bounding_box = ((0, 10), (0, 20))
```

the ``pixel_bounds`` are defined, which is good:

```python
In [3]: wcsobj.pixel_bounds
Out[3]: ((0, 10), (0, 20))
```

However, these pixel bounds currently only apply to pixel to world transformations:

```python
In [4]: print(wcsobj.pixel_to_world(10, 10))
   ...:
<SkyCoord (ICRS): (ra, dec) in deg
    (29.98075555, 44.98638727)>

In [5]: print(wcsobj.pixel_to_world(30, 10))
<SkyCoord (ICRS): (ra, dec) in deg
    (nan, nan)>
```

and not world to pixel transformations:

```python
In [6]: wcsobj.world_to_pixel(SkyCoord(30, 50, unit="deg"))
Out[6]: [500.0000000002625, 180958.32230992112]
```

However, this should return ``[nan, nan]``.

### Additional contract requirements

The bounding box is applied independently to each pixel axis of the inverse
(world to pixel) transform. When the inverse transform produces pixel
coordinates outside the bounding box, an axis whose value lies outside that
axis' bounding box interval is set to ``nan``, while an axis whose value lies
inside its interval is returned unchanged. For example, with a bounding box of
``((0, 63), (0, 127), (0, 255), (0, 9))``, inverting a world coordinate whose
pixel coordinates are ``(100, 3, 3, 3)`` returns ``(nan, 3, 3, 3)``.
