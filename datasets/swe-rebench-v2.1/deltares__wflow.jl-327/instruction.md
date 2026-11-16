Support Total Water Storage (`SBM` concept) as output variable
Requested to allow for convenient comparison to GRACE satellite data.

### Additional contract requirements

Expose the output through the stable identifier `vertical.total_storage`. For each active SBM cell, its value is the current total water storage in millimetres. It includes glacier storage weighted by glacier fraction, snow, snow water, canopy storage, unsaturated and saturated subsurface water depths, land-routing water level weighted by the non-river fraction, and the river-routing water contribution. The river contribution is river water level multiplied by river width and river length, divided by cell area, and converted to millimetres. Floodplain, lake, and reservoir storage are excluded. Refresh the output when each model timestep completes so it reflects the model's current state.
