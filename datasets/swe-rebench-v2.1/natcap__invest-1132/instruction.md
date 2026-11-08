Urban Stormwater: soil raster as float type causes index error
A user on the [forum](https://community.naturalcapitalproject.org/t/urban-stormwater-retention-model-indexerror/3052/2) was encountering an interesting bug:

```python
2022-09-15 13:30:43,132 (pygeoprocessing.geoprocessing) geoprocessing.raster_calculator(498) ERROR exception encountered in raster_calculator
Traceback (most recent call last):
  File "pygeoprocessing\geoprocessing.py", line 443, in raster_calculator
  File "natcap\invest\stormwater.py", line 671, in ratio_op
IndexError: arrays used as indices must be of integer (or boolean) type
2022-09-15 13:30:43,133 (pygeoprocessing.geoprocessing) geoprocessing.raster_calculator(513) INFO Waiting for raster stats worker result.
2022-09-15 13:30:43,134 (pygeoprocessing.geoprocessing_core) threading.run(946) WARNING No valid pixels were received, sending None.
2022-09-15 13:30:43,134 (taskgraph.Task) Task.add_task(706) ERROR Something went wrong when adding task calculate stormwater retention ratio (1), terminating taskgraph.
Traceback (most recent call last):
  File "taskgraph\Task.py", line 674, in add_task
  File "taskgraph\Task.py", line 1093, in _call
  File "natcap\invest\stormwater.py", line 674, in lookup_ratios
  File "pygeoprocessing\geoprocessing.py", line 443, in raster_calculator
  File "natcap\invest\stormwater.py", line 671, in ratio_op
IndexError: arrays used as indices must be of integer (or boolean) type
```

This occurs in: https://github.com/natcap/invest/blob/41070ee205506d8000f14ba2d81a53567d1882b7/src/natcap/invest/stormwater.py#L658

During a numpy array indexing call the soil array is being used as an index, but it has a floating point types, which causes the error.

The solution here could be to just handle floating point soil inputs or to validate upfront that the soil raster is of integer type.
