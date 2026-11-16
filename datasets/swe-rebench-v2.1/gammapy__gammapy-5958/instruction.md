TSMapEstimator fails for some values of sigma with using a GaussianSpatialModel
**Gammapy version**
Both 1.2 and  dev

**Bug description**
Hi, I am having a strange error with the `TSMapEstimator`. I am running it on a dataset using a `GaussianSpatialModel`. If I set sigma=0.15º, it works, but 0.16º (or higher) does not.

The issue arises both in 1.2 and the dev version, although the error message is slightly different.

Because the error message (pasted below) is related to broadcasting of the kernel, I suspected a numpy/astropy version problem. But on my dev environment I have numpy>2 and astropy>7 and the error persists.


Since my dataset has private data, I made a toy example with a dataset that attempts to get as close to mine as possible. I clearly did not manage completely because while I reproduce the error, the boundary is now between 0.2 and 0.21º degree. I pasted it below.

**To Reproduce**
```
from gammapy.irf import PSFMap, EDispKernelMap
from gammapy.maps import MapAxis,WcsGeom
import numpy as np
import astropy.units as u
from astropy.coordinates import SkyCoord
from gammapy.estimators import TSMapEstimator
from gammapy.modeling.models import GaussianSpatialModel, PowerLawSpectralModel, SkyModel
from gammapy.datasets import MapDataset


energy_axis = MapAxis.from_energy_bounds(0.8*u.TeV,80*u.TeV, nbin=14, name='energy')


energy_axis_true = MapAxis.from_energy_bounds("0.1 TeV", "100 TeV", nbin=20, per_decade=True, name="energy_true")

center = SkyCoord(l = 6.773950 ,b= -4.789072 , unit='deg', frame='galactic')

geom = WcsGeom.create(binsz = 0.01,
                        skydir =center,
                        width = 3*u.deg,
                        frame = 'galactic',
                        axes = [energy_axis])

test = MapDataset.create(geom, energy_axis_true)
test.exposure.data = 1
test.background.data = 2
test.counts.data = 3
test.mask_safe.data = True
test.psf = PSFMap.from_gauss(energy_axis_true, rad_axis =test.psf.psf_map.geom.axes["rad"], geom = test.psf.psf_map.geom.to_image())
test.edisp = EDispKernelMap.from_gauss(energy_axis,energy_axis_true, sigma=0.1, bias =0,  geom = test.edisp.edisp_map.geom.to_image())


# 0.2 will work
ts_estimator1 = TSMapEstimator(SkyModel(spatial_model=GaussianSpatialModel(sigma=0.2*u.deg), spectral_model=PowerLawSpectralModel(index=2)),
                      selection_optional = [], energy_edges =[0.8, 5,22]*u.TeV, n_jobs=6)

result_1 = ts_estimator1.run(test)
print(result_1)



# 0.21 will not
ts_estimator2 = TSMapEstimator(SkyModel(spatial_model=GaussianSpatialModel(sigma=0.21*u.deg), spectral_model=PowerLawSpectralModel(index=2)),
                      selection_optional = [], energy_edges =[0.8, 5,22]*u.TeV, n_jobs=6)

result_2 = ts_estimator2.run(test)
print(result_2)
```

Error message with gammapy 1.2 (the specific numbers in the error depend on sigma)
```
(gammapy-1.2) [nieto@lfs1 ~]$ python test_kernel_error.py
FluxMaps
--------

  geom                   : WcsGeom
  axes                   : ['lon', 'lat', 'energy']
  shape                  : (300, 300, 2)
  quantities             : ['ts', 'norm', 'niter', 'norm_err', 'npred', 'npred_excess', 'stat', 'stat_null', 'success']
  ref. model             : pl
  n_sigma                : 1
  n_sigma_ul             : 2
  sqrt_ts_threshold_ul   : 2
  sed type init          : likelihood

multiprocessing.pool.RemoteTraceback:
"""
Traceback (most recent call last):
  File "/nfs/scratch/nieto/miniforge3/envs/gammapy-1.2/lib/python3.10/multiprocessing/pool.py", line 125, in worker
    result = (True, func(*args, **kwds))
  File "/nfs/scratch/nieto/miniforge3/envs/gammapy-1.2/lib/python3.10/multiprocessing/pool.py", line 51, in starmapstar
    return list(itertools.starmap(args[0], args[1]))
  File "/nfs/scratch/nieto/miniforge3/envs/gammapy-1.2/lib/python3.10/site-packages/gammapy/estimators/map/ts.py", line 837, in _ts_value
    dataset = SimpleMapDataset.from_arrays(
  File "/nfs/scratch/nieto/miniforge3/envs/gammapy-1.2/lib/python3.10/site-packages/gammapy/estimators/map/ts.py", line 595, in from_arrays
    model=kernel * exposure_cutout,
ValueError: operands could not be broadcast together with shapes (1,303,303) (1,0,0)
"""

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "/nfs/us0/nieto/test_kernel_error.py", line 46, in <module>
    result_2 = ts_estimator2.run(test)
  File "/nfs/scratch/nieto/miniforge3/envs/gammapy-1.2/lib/python3.10/site-packages/gammapy/estimators/map/ts.py", line 510, in run
    result = self.estimate_flux_map(dataset_sliced)
  File "/nfs/scratch/nieto/miniforge3/envs/gammapy-1.2/lib/python3.10/site-packages/gammapy/estimators/map/ts.py", line 433, in estimate_flux_map
    results = parallel.run_multiprocessing(
  File "/nfs/scratch/nieto/miniforge3/envs/gammapy-1.2/lib/python3.10/site-packages/gammapy/utils/parallel.py", line 283, in run_multiprocessing
    results = pool_func(
  File "/nfs/scratch/nieto/miniforge3/envs/gammapy-1.2/lib/python3.10/site-packages/gammapy/utils/parallel.py", line 313, in run_pool_star_map
    return pool.starmap(func, progress_bar(inputs, desc=task_name), **method_kwargs)
  File "/nfs/scratch/nieto/miniforge3/envs/gammapy-1.2/lib/python3.10/multiprocessing/pool.py", line 375, in starmap
    return self._map_async(func, iterable, starmapstar, chunksize).get()
  File "/nfs/scratch/nieto/miniforge3/envs/gammapy-1.2/lib/python3.10/multiprocessing/pool.py", line 774, in get
    raise self._value
ValueError: operands could not be broadcast together with shapes (1,303,303) (1,0,0)
```
Error message with the dev version
```
(gammapy-dev) [nieto@lfs1 ~]$ python test_kernel_error.py
FluxMaps
--------

  geom                   : WcsGeom
  axes                   : ['lon', 'lat', 'energy']
  shape                  : (np.int64(300), np.int64(300), 2)
  quantities             : ['ts', 'norm', 'niter', 'norm_err', 'npred', 'npred_excess', 'stat', 'stat_null', 'success']
  ref. model             : pl
  n_sigma                : 1
  n_sigma_ul             : 2
  sqrt_ts_threshold_ul   : 2
  sed type init          : likelihood

multiprocessing.pool.RemoteTraceback:
"""
Traceback (most recent call last):
  File "/nfs/scratch/nieto/miniforge3/envs/gammapy-dev/lib/python3.11/multiprocessing/pool.py", line 125, in worker
    result = (True, func(*args, **kwds))
                    ^^^^^^^^^^^^^^^^^^^
  File "/nfs/scratch/nieto/miniforge3/envs/gammapy-dev/lib/python3.11/multiprocessing/pool.py", line 51, in starmapstar
    return list(itertools.starmap(args[0], args[1]))
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/nfs/d22/hin/nieto/gammapy/gammapy/estimators/map/ts.py", line 1068, in _ts_value
    SimpleMapDataset.from_arrays(
  File "/nfs/d22/hin/nieto/gammapy/gammapy/estimators/map/ts.py", line 711, in from_arrays
    kernel = (kernel * weights).sum(axis=0, keepdims=True)
              ~~~~~~~^~~~~~~~~
ValueError: operands could not be broadcast together with shapes (6,303,303) (6,0,0)
"""

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "/nfs/us0/nieto/test_kernel_error.py", line 46, in <module>
    result_2 = ts_estimator2.run(test)
               ^^^^^^^^^^^^^^^^^^^^^^^
  File "/nfs/d22/hin/nieto/gammapy/gammapy/estimators/map/ts.py", line 626, in run
    result = self.estimate_flux_map(datasets_sliced)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/nfs/d22/hin/nieto/gammapy/gammapy/estimators/map/ts.py", line 507, in estimate_flux_map
    results = parallel.run_multiprocessing(
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/nfs/d22/hin/nieto/gammapy/gammapy/utils/parallel.py", line 288, in run_multiprocessing
    results = pool_func(
              ^^^^^^^^^^
  File "/nfs/d22/hin/nieto/gammapy/gammapy/utils/parallel.py", line 318, in run_pool_star_map
    return pool.starmap(func, progress_bar(inputs, desc=task_name), **method_kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/nfs/scratch/nieto/miniforge3/envs/gammapy-dev/lib/python3.11/multiprocessing/pool.py", line 375, in starmap
    return self._map_async(func, iterable, starmapstar, chunksize).get()
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/nfs/scratch/nieto/miniforge3/envs/gammapy-dev/lib/python3.11/multiprocessing/pool.py", line 774, in get
    raise self._value
ValueError: operands could not be broadcast together with shapes (6,303,303) (6,0,0)
``

**Other information**
Any other information you think will be useful for us to fix the issue can go here.

### Additional contract requirements

- `TSMapEstimator` accepts a `kernel_width` argument (an angle, for example `10 * u.deg`). When it is provided, the datasets are padded using that width.
- The `TSMapEstimator.kernel_width` attribute holds the user-provided width. When `kernel_width` is omitted, it is set to the maximum kernel width computed from the input datasets.
