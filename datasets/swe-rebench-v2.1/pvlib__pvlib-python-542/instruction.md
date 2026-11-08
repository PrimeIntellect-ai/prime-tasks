pvwatts_ac returns values less than 0
**Describe the bug**
The pvwatts ac power model is proportional to the quantity ``eta`` as defined by

```
zeta = pdc / pdc0
eta = -0.0162*zeta - 0.0059/zeta + 0.9858
```

``eta`` is negative for ``eta < 0.006`` or so. While ac power less than 0 is not unphysical, I don't think the intention was for the PVWatts AC model to yield these values. I don't see any explicit reference to this in the PVWatts manual.

**To Reproduce**
Run ``pvwatts_ac`` with a pdc value that is less than 0.006 of pdc0.

**Expected behavior**
0 should be returned for these values instead.

**Screenshots**

![download-5](https://user-images.githubusercontent.com/4383303/44425810-d16f7500-a541-11e8-86db-026d8324f30f.png)


**Versions:**
 - ``pvlib.__version__``: '0.5.2+35.g0aa4d2e'
 - ``pandas.__version__``: n/a
 - python: n/a
