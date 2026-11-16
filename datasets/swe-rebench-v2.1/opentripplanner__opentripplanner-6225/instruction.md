Cannot refetch alert using Relay id
**NOTE:** this issue system is intended for reporting bugs and tracking progress in software
development. For all other usage and software development questions or discussion, please post a
question in our chat room: https://gitter.im/opentripplanner/OpenTripPlanner.


## Expected behavior
The alert is retrieved.

## Observed behavior
It returns null.

Note that the bug doesn't exist on routes.

## Version of OTP used (exact commit hash or JAR name)
2.7.0-SNAPSHOT

## Data sets in use (links to GTFS and OSM PBF files)
Any GTFS-RT feeds which include alerts

## Command line used to start OTP

## Router config and graph build config JSON

## Steps to reproduce the problem
1. Run the following query
```graphql
query GtfsExampleQuery {
  alerts {
    id
  }
}
```
2. Run the following query
```graphql
query GtfsExampleQuery {
    node(id : $id) {
         id
    }
}
````
using one of the IDs return from the above.
