bicycle_road=yes does not improve the bike safety of a way in any of *WayPropertySetSource.java
## Expected behavior
Dedicated bicycle_roads improve the bike safety of a segment, attracting itineraries from parallel streets.
https://wiki.openstreetmap.org/wiki/Key:bicycle_road
https://wiki.openstreetmap.org/wiki/Key:cyclestreet

## Observed behavior
It does not.

## Version of OTP used (exact commit hash or JAR name)
Version:    2.1.0-SNAPSHOT
Ser.ver.id: 14
Commit:     8a9f525f31e8d788656f8a82eccf07015a950726
Branch:     dev-2.x
Build:      2021-12-03T16:20:37+0000

## Data sets in use (links to GTFS and OSM PBF files)
Using an extract of https://download.geofabrik.de/europe/germany-latest.osm.pbf

## Command line used to start OTP
java -Xms1G -Xmx2G -jar otp-shaded.jar --load --serve /opt/opentripplanner/graph/

## Router config and graph build config JSON

## Steps to reproduce the problem
Open the bike safety debugging layer and look at a bicycle_street

### Additional contract requirements

- For a residential way, `bicycle_road=yes` alone, `cyclestreet=yes` alone, and `lcn=yes` alone must have equal forward bicycle safety values. A residential way tagged with `bicycle_road=yes`, `cyclestreet=yes`, and `lcn=yes` must have the same forward bicycle safety value as each of those individual cases, with a value of 0.6859. An otherwise untagged residential way must have a forward bicycle safety value of 0.98.
