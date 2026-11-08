Error with new Constant type in database
This example script:

https://github.com/Jammy2211/autolens_workspace_test/blob/main/scripts/database/scrape/slam_pix.py

Gives this error:

```
2024-11-21 17:47:48,638 - autofit.database.aggregator.aggregator - INFO - 1 fit(s) found matching query
TracerAgg with linear light profiles raises correct ProfileException
TracerAgg Checked
2024-11-21 17:47:48,756 - autoarray.dataset.imaging.dataset - INFO - IMAGING - Data masked, contains a total of 716 image-pixels
ImagingAgg Checked
2024-11-21 17:47:49,190 - autoarray.dataset.imaging.dataset - INFO - IMAGING - Data masked, contains a total of 716 image-pixels
Traceback (most recent call last):
  File "/mnt/c/Users/Jammy/Code/PyAuto/autolens_workspace_test/scripts/database/scrape/slam_pix.py", line 388, in <module>
    fit_plotter.subplot_fit()
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoLens/autolens/imaging/plot/fit_imaging_plotters.py", line 435, in subplot_fit
    self.figures_2d(data=True)
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoLens/autolens/imaging/plot/fit_imaging_plotters.py", line 755, in figures_2d
    visuals_2d = self.get_visuals_2d()
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoLens/autolens/imaging/plot/fit_imaging_plotters.py", line 71, in get_visuals_2d
    return self.get_2d.via_fit_imaging_from(fit=self.fit)
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoLens/autolens/plot/get_visuals/two_d.py", line 171, in via_fit_imaging_from
    visuals_2d_via_tracer = self.via_tracer_from(
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoLens/autolens/plot/get_visuals/two_d.py", line 80, in via_tracer_from
    tracer.planes[plane_index].extract_attribute(
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoLens/autolens/lens/tracer.py", line 212, in planes
    galaxies=self.galaxies_ascending_redshift,
  File "/mnt/c/Users/Jammy/Code/PyAuto/PyAutoLens/autolens/lens/tracer.py", line 155, in galaxies_ascending_redshift
    return sorted(self.galaxies, key=lambda galaxy: galaxy.redshift)
TypeError: '<' not supported between instances of 'Constant' and 'float'
```

Presuambly the constants refactor.

### Additional contract requirements

- `ModelObject` (the base class of `Constant`, in `autofit.mapper.model_object`) exposes an `id` property. Reading `id` returns the object's integer identifier. Assigning a non-integer value such as `1.0` results in an integer identifier.
- `Constant` (in `autofit.mapper.prior.constant`) provides `dict()`, which returns a dictionary representation of the constant, and the class method `from_dict(data)`, which reconstructs a `Constant` from such a dictionary.
- Comparing and sorting `Constant` instances together with plain numbers must work, ordering them by their numeric value, and must not raise `TypeError`.
- Two separately created `Constant(1.0)` instances have different `hash()` values.
- A `Constant` reconstructed with `Constant.from_dict(constant.dict())` has a nonzero `hash()` value.
- After assigning `1.0` to a `Constant`'s `id`, `hash(constant)` is nonzero.
