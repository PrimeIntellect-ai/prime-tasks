trackintel-postgis connector fails when using mixed timezones
reading staypoints from a postgis database with timestamps with mixed timezones results in the following error when using `assert spts.as_staypoints`:
```
  File "C:\Users\henry\.conda\envs\graph_rep\lib\site-packages\trackintel\model\staypoints.py", line 60, in _validate
    assert pd.api.types.is_datetime64tz_dtype(
AssertionError: dtype of started_at is object but has to be tz aware datetime64
```
This seems to be a pandas-posgresql problem where we can not do much about it but we can solve the problem by transforming data to UTC after reading it from the database.
[HIDDEN]
I have ran some quick tests and what it does is that transforms the timezone to UTC without losing the time information (e.g., 13:33+02 -->11:33+00) however I am not sure what happens if no tz is provided

### Additional contract requirements

- Reading positionfixes, staypoints, or trips from a GeoDataFrame with the public functions `read_positionfixes_gpd`, `read_staypoints_gpd`, and `read_trips_gpd` must convert timestamp columns that contain mixed timezones to UTC, just as when reading from PostGIS.
- For staypoints, both `started_at` and `finished_at` must be normalized.
