Better handling for missing ferry duration tags
If there is no duration tag on a ferry we currently use `speed=5km/h`, or even smaller if the distance is below 300m. But for longer distance ferries this seems very likely too slow. Also I think not tagging duration for such longer ferries is a mapping error and if this happens frequently we should report it to OSM.

Also see here: https://github.com/graphhopper/graphhopper/pull/2528/files#r819521430

### Additional contract requirements

- The ferry speed is computed by `FerrySpeedCalculator.getSpeed(ReaderWay way)`, which returns the speed in km/h.
- The method reads the artificial tags `speed_from_duration` (a speed in km/h derived from a duration tag) and `edge_distance` (the distance of the edge in metres).
- When `speed_from_duration` is present, the returned speed is based on it.
- When `speed_from_duration` is absent, edges shorter than 500 m use the minimum speed; edges of 500 m or longer use the unknown speed.
- The returned speed is never below the minimum speed nor above the maximum speed.
- When neither `speed_from_duration` nor `edge_distance` is present, an `IllegalStateException` is thrown.
- For an edge distance of 1000 m with no duration-derived speed, the result is 5 km/h.
