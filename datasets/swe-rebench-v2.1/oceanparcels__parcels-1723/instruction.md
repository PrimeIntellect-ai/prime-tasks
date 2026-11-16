Backward in time outputs not written at desired frequency
### Parcels version

3.0.5

### Description

Looks like a regression from 3.0.4 to 3.0.5.

### Code sample

```python
from datetime import timedelta
import xarray as xr
import numpy as np
import parcels

example_dataset_folder = parcels.download_example_dataset("MovingEddies_data")
fieldset = parcels.FieldSet.from_parcels(f"{example_dataset_folder}/moving_eddies")

pset = parcels.ParticleSet.from_list(
    fieldset=fieldset,
    pclass=parcels.JITParticle,
    lon=[3.3e5, 3.3e5],
    lat=[1e5, 2.8e5],
)

# run forward

output_file = pset.ParticleFile(
    name="EddyParticles.zarr",
    outputdt=timedelta(hours=1),
)
pset.execute(
    parcels.AdvectionRK4,
    runtime=timedelta(days=2),
    dt=timedelta(minutes=5),
    output_file=output_file,
)

# run backward

output_file = pset.ParticleFile(
    name="EddyParticles_Bwd.zarr",
    outputdt=timedelta(hours=1),
)
pset.execute(
    parcels.AdvectionRK4,
    runtime=timedelta(days=2),
    dt=-timedelta(minutes=5),
    output_file=output_file,
)

# check that timesteps match (up to a sign)

ds = xr.open_zarr("EddyParticles.zarr/")
ds_bwd = xr.open_zarr("EddyParticles_Bwd.zarr/")

np.testing.assert_almost_equal(
    ds.time.isel(trajectory=0).diff("obs").mean().compute().astype(float).data[()],
    - ds_bwd.time.isel(trajectory=0).diff("obs").mean().compute().astype(float).data[()],
)
```

With `v3.0.5`:
```text
AssertionError:
Arrays are not almost equal to 7 decimals
 ACTUAL: 3600000000000.0
 DESIRED: 86400000000000.0
```

With `v3.0.4` it works.
