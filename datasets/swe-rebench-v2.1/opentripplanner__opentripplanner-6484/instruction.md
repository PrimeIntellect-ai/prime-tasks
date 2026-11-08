Rounding error in A*
Some trip searches trigger the following warning in the logs:

`A graph path arrives after the requested time. This implies a bug`

Debugging a few occurrences of this bug shows that the difference between arrival time and requested time is always 1s.

It seems this is a side-effect of https://github.com/opentripplanner/OpenTripPlanner/pull/6436


## Version of OTP used (exact commit hash or JAR name)
Latest dev-2x

## Data sets in use (links to GTFS and OSM PBF files)
Norwegian dataset.

### Additional contract requirements

- For an arrive-by walking search on the roundabout from (59.94646, 10.77511) to (59.94641, 10.77522), with the requested time at 0, 200, 400, 499, 500, 501, 600, 700, 800, 900, or 999 milliseconds after a whole-second boundary, the elapsed time between the first and last states' accurate times must be exactly 13,926 ms.
