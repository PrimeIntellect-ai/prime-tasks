Urban Nature Access: handle the case where an admin boundary doesn't overlap any people
A [user on the forums](https://community.naturalcapitalproject.org/t/something-went-wrong-when-adding-task-aggregate-supply-demand-to-admin-units-single-rasters-17/4405) encountered a `ZeroDivisionError` that appears to be caused by an admin boundary polygon that doesn't overlap any people in the population raster.  The workaround suggested to the user was to locate that polygon and remove it from the vector until a fix can be implemented.

### Additional contract requirements

An administrative unit with no overlapping population must remain in the summary output. Its per-capita supply/demand result must have no numeric value; a null/None or NaN representation is acceptable.
