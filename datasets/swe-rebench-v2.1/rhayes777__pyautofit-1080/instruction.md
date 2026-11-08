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

- A `Constant` redshift value must support the less-than operator against plain numeric values, comparing its wrapped value with the number. This holds in either operand order (`Constant(1.0) < 2.0` and `1.0 < Constant(2.0)`).
- Sorting a list that mixes `Constant` redshift values with plain float redshifts must succeed and order the items by their numeric values.
