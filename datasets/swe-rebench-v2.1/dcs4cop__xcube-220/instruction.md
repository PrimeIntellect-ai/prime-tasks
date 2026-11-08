Resample .zarr Cube
**Describe the bug**
Error during the xcube resample for Sentinel-2 dataset.

**To Reproduce**
1. Generate the Sentinel-2 MSI irregular time cube using the `xcube gen`.

To generate it I took the netCDF files (tiles 31UET, 31UES, 31UDT, 31UDS).

**I use the config parameters:**
![TICKET01_01](https://user-images.githubusercontent.com/32440152/67864720-58e14c80-fb26-11e9-91db-e0fcaa0c152f.png)

The **output_size** and **output_region** I took from `xcube grid abox`:
![TICKET01_02](https://user-images.githubusercontent.com/32440152/67864773-77474800-fb26-11e9-8526-7855d69ab2b5.png)

**The .zarr cube was created with no errors.**
![ticket01_06](https://user-images.githubusercontent.com/32440152/67864968-c7bea580-fb26-11e9-87da-cf69c515be50.png)

**2. Run the `xcube resample` with the command line:**
![ticket01_03](https://user-images.githubusercontent.com/32440152/67865040-e9b82800-fb26-11e9-990c-8d9881cb53bd.png)

**HERE IS THE ERROR MESSAGE:**
![xcube_ticket01_resample_issue_with_chunk](https://user-images.githubusercontent.com/32440152/67864136-71049c00-fb25-11e9-8e33-5c156fd7f554.png)

**Run again the `xcube resample` but now with output as netCDF4:**
![ticket01_04](https://user-images.githubusercontent.com/32440152/67865109-0f453180-fb27-11e9-95e4-bbf64fc17b46.png)

**With output as netCDF4 the resample successfully finished.**
![ticket01_05](https://user-images.githubusercontent.com/32440152/67865248-461b4780-fb27-11e9-8c0d-54539ca9e651.png)

**Expected behavior**
I was expected to resample using as output the .zarr format (netCDF4 is too big and too slow).

**Screenshots**
Added during the text.

**Desktop (please complete the following information):**
 - OS: Linux Ubuntu 18.04
 - Browser: Firefox (not necessary)
 - Version: concerning the xcube version I updated the xcube and xcube-gen-bc before start (30/10/2019)

**Additional context**
I used the same `xcube resample` before for the Sentinel-3 (full North Sea) and it worked perfect to generate the 1D resample cube in .zarr format. **I think my problem is due the chunk option.**
What should I do to edit the chunk size to a *ideal match*.

Thank you for the help!!

### Additional contract requirements

The fix must expose and honour the following public API.

### `xcube.core.chunk.chunk_dataset`

`chunk_dataset(dataset, chunk_sizes=None, format_name=None)` in module `xcube.core.chunk`
returns a dataset re-chunked according to `chunk_sizes`, a mapping from dimension name to the
desired chunk size. When `format_name` is `"zarr"`, each variable's `encoding` is updated with a
`"chunks"` entry; when `format_name` is `"netcdf4"`, each variable's `encoding` is updated with a
`"chunksizes"` entry. The recorded chunk sizes follow the requested `chunk_sizes` and, for
dimensions not named there, the dataset's existing Dask chunks.

### `xcube.core.resample.resample_in_time`

`resample_in_time(cube, frequency, method, offset=None, base=0, tolerance=None, interp_kind=None, time_chunk_size=None, var_names=None, metadata=None, cube_asserted=False)`
in module `xcube.core.resample` returns a new cube resampled along the `time` dimension.

- The result is chunked according to the input cube's chunk layout. If `time_chunk_size` is an
  integer, it overrides the chunk size used for the `time` dimension.
- If `cube_asserted` is false, the input cube is validated as an xcube dataset and a `ValueError`
  is raised if it is not valid; if `cube_asserted` is true, this validation is skipped.
- If `var_names` is given, only the named variables are included in the result.
- If `metadata` is given, its entries are added to the result's attributes.
- `offset` shifts the resampled time labels by the given pandas offset.
- `base` sets the origin of the aggregated intervals for frequencies that subdivide a day.
- `tolerance` is the maximum distance allowed when up-sampling with methods that select existing
  values.
- `interp_kind` selects the interpolation kind when `method` is `"interpolate"`.

The resampled cube can be written to Zarr. The `xcube resample` command must produce a readable Zarr output, using a storage chunk size of one along the time dimension by default.
