WcsNDmap fill_by_coord creating strange wavy patterns in spectra
**Gammapy version**
Dev version

**Bug description**
Creating a WcsNDmap with `fill_by_coord`, for example a spectrum, doesn't give the same results as plt.hist() as shown below :

![Capture d’écran 2024-07-04 à 16 57 19](https://github.com/gammapy/gammapy/assets/8652898/8e39e0f8-c1c2-4c05-901a-df0a18d73be3)

**Expected behavior**
Here I generated a fake event list with regularly spaced energies where one would expect 2 counts per energy bin.
We see wavy structure to assigning events sometimes to the left bin or to the right energy bin.
plt.hist() has correctly 2 counts in every bin.

Note that in the MRE if one changes
evt_energy = np.arange(1000.,1020,0.5)*u.GeV
to
evt_energy = np.arange(1000.0001,1020,0.5)*u.GeV

this produces a flat spectrum as expected.

[HIDDEN]

**To Reproduce**
Here is a minimal example :

```
import numpy as np
import matplotlib.pyplot as plt
from astropy.coordinates import SkyCoord
from astropy import units as u
from gammapy.maps import WcsGeom, WcsNDMap, MapAxis

E_edges=np.arange(1000,1021,1) *u.GeV #define some edges
evt_energy = np.arange(1000.,1020,0.5)*u.GeV #a fake photon event energy list
print(f'E_edges= {E_edges}')
print(f'E_evt= {evt_energy}')

N_evt = evt_energy.shape[0]
radec = SkyCoord([center.ra]*N_evt, [center.dec]*N_evt,frame='fk5',unit="deg" ) #fake position list
energy_axis = MapAxis.from_edges(E_edges,name='energy')

map = WcsNDMap.create(skydir=center, binsz=0.1*u.deg, width=0.1*u.deg, frame='icrs', axes=[energy_axis], proj='CAR')
map.fill_by_coord({'skycoord': radec, 'energy': evt_energy})

spec = map.data.sum(axis=(1,2))
plt.plot(energy_axis.center, spec, marker='o',label='WcsNDMap fill_by_coord')
h=plt.hist(evt_energy, bins=E_edges,histtype='step',label='plt.hist')
plt.legend()
plt.show()
# both histogram don't look alike why !!??
```

### Additional contract requirements

- For `fill_by_pix` on a 3-by-3 WCS map, filling pixel coordinates `[[0.0, 0.5, 1.0, 1.5], [0.0, 0.5, 1.0, 1.5]]` must produce data `[[1.0, 0.0, 0.0], [0.0, 2.0, 0.0], [0.0, 0.0, 1.0]]`.
- For the regularly spaced energies in the reproduction, `fill_by_coord` must produce a spectrum with two counts in every energy bin, matching the histogram.
