Performance issue with vertex linking in complex area
The following Transmodel query takes about 50s to complete, spending most of the computation time in org.opentripplanner.routing.linking.VertexLinker.link()

```
query getTripPatternsForBikeRental($from: Location!, $to: Location!, $walkSpeed: Float) {
  trip(
    from: $from,
    to: $to,
    modes: {
      directMode: bike_rental
    },
    walkSpeed: $walkSpeed,
    numTripPatterns: 1
  ) {
    tripPatterns {
      duration
      legs {
        mode
        fromPlace {
          bikeRentalStation {
            id
            name
            bikesAvailable
            spacesAvailable
            __typename
          }
          __typename
        }
        toPlace {
          bikeRentalStation {
            id
            name
            bikesAvailable
            spacesAvailable
            __typename
          }
          __typename
        }
        __typename
      }
      __typename
    }
    __typename
  }
}

```
variables:

```
{
  "from": {
    "coordinates": {
      "latitude": 59.91095,
      "longitude": 10.729659
    }
  },
  "to": {
    "coordinates": {
      "latitude": 59.912763,
      "longitude": 10.73132
    }
  },
  "walkSpeed": 1.3
}
```
Profiling seems to show that time is spent in org.opentripplanner.routing.linking.VertexLinker#addAreaVertex()
https://github.com/opentripplanner/OpenTripPlanner/blob/05e365567c926d3af623a994f61a7181c8255bf3/src/main/java/org/opentripplanner/routing/linking/VertexLinker.java#L550
![Screenshot from 2023-06-19 15-50-57](https://github.com/opentripplanner/OpenTripPlanner/assets/46598384/b64a356e-300d-4cde-b56d-3065becaac20)


When using a street graph covering all Norway, the query returns in about 50s.
When using a street graph covering only the Oslo area, the query returns in about 20s.

The start location is dense:
![Screenshot from 2023-06-19 16-23-56](https://github.com/opentripplanner/OpenTripPlanner/assets/46598384/0d9ec8b3-06a3-4d6e-803c-5548cd896d9d)


## Version of OTP used (exact commit hash or JAR name)
dev-2.x

## Data sets in use (links to GTFS and OSM PBF files)

Transit data: https://storage.googleapis.com/marduk-dev/osm/extract/rb_rut-aggregated-netex.zip
OSM Norway: https://download.geofabrik.de/europe/norway-latest.osm.pbf

## Command line used to start OTP

## Router config and graph build config JSON
Build config:

```
{
  "transitModelTimeZone" : "Europe/Oslo",
  "transitServiceStart" : "2023-01-01",
  "transitServiceEnd": "2023-12-31",
  "dataImportReport": true,
  "subwayAccessTime": 0,
  "embedRouterConfig": true,
  "areaVisibility": true,
  "platformEntriesLinking": true,
  "matchBusRoutesToStreets": false,
  "staticParkAndRide": true,
  "staticBikeParkAndRide": true,
  "maxDataImportIssuesPerFile": 1000,
  "banDiscouragedWalking": false,
  "banDiscouragedBiking": false,
  "maxTransferDuration": "30m",
  "distanceBetweenElevationSamples": 25,
  "multiThreadElevationCalculations": true,
  "boardingLocationTags": [],
  "netexDefaults": {
    "sharedFilePattern": "_stops.xml",
    "sharedGroupFilePattern": "_(\\w{3})(_flexible)?_shared_data.xml",
    "groupFilePattern": "(\\w{3})_.*\\.xml",
    "feedId": "RB",
    "ferryIdsNotAllowedForBicycle": [
      "NYC:Line:1",
      "NYC:Line:012fc5c4-131b-4dfc-8160-4e49136e531a",
      "NYC:Line:8bfef12a-ac98-4376-8a2a-eb5a336d107b"
    ]
  },
  "osmCacheDataInMem": "true",
  "osmDefaults":
    	{
    	  "osmTagMapping": "norway",
    	  "timeZone": "Europe/Oslo"
    	},
  "osm": [
    	{
     	  "source": "https://download.geofabrik.de/europe/norway-latest.osm.pbf",
     	  "osmTagMapping": "norway",
    	  "timeZone": "Europe/Oslo"
    	}

  ],
  "streetGraph": "streetGraph-${otp.serialization.version.id}.obj",
  "graph": "graph-${otp.serialization.version.id}.obj",
  "buildReportDir": "report",
  "transitFeeds": [
    	{
          "type": "netex",
    	  "feedId": "RB",
  	  "source": "https://storage.googleapis.com/marduk-dev/osm/extract/rb_rut-aggregated-netex.zip",

    	  "sharedFilePattern": "_stops.*\\.xml",
          "sharedGroupFilePattern": "_(\\w{3})(_flexible)?_shared_data.xml"
    	}
    ]
}
```
Router config:

```
 {
        "configVersion" : "1",
        "server": {
           "apiProcessingTimeout" : "300s"
        },
        "routingDefaults": {
          "streetRoutingTimeout": "5s",
          "walkSpeed": 1.3,
          "bikeSpeed": 5,
          "carSpeed": 40,
          "numItineraries": 12,
          "transferPenalty": 0,
          "walkReluctance": 4.0,
          "bikeReluctance": 5.0,
          "bikeWalkingReluctance": 10.0,
          "carReluctance": 10.0,
          "stairsReluctance": 1.65,
          "turnReluctance": 1.0,
          "elevatorBoardTime": 90,
          "elevatorBoardCost": 90,
          "elevatorHopTime": 20,
          "elevatorHopCost": 20,
          "bikeParkTime": 60,
          "bikeParkCost": 120,
          "carDropoffTime": 120,
          "waitReluctance": 1.0,
          "walkBoardCost": 600,
          "bikeBoardCost": 600,
          "otherThanPreferredRoutesPenalty": 300,
          "transferSlack": 120,
          "boardSlackForMode": {
            "AIRPLANE" : "35m"
          },
          "alightSlackForMode": {
            "AIRPLANE" : "15m"
          },
          "transitReluctanceForMode" : {
            "RAIL" : 0.85
          },
          "maxAccessEgressDurationForMode": {
            "BIKE_RENTAL": "20m"
          },
          "maxDirectStreetDurationForMode": {
            "CAR": "12h"
          },
          "itineraryFilters" : {
            "transitGeneralizedCostLimit" : {
              "costLimitFunction": "900 + 1.5x",
              "intervalRelaxFactor": 0.75
            },
            "bikeRentalDistanceRatio": 0.3
          },
          "carDecelerationSpeed": 2.9,
          "carAccelerationSpeed": 2.9,
          "ignoreRealtimeUpdates": false,
          "geoidElevation": false,
          "maxJourneyDuration": "36h",
          "drivingDirection": "right",
          "transferOptimization": {
            "optimizeTransferWaitTime": true,
            "minSafeWaitTimeFactor": 5.0,
            "backTravelWaitTimeFactor": 1.0,
            "extraStopBoardAlightCostsFactor": 8.0
          }
        },
        "transit": {
          "maxNumberOfTransfers" : 12,
          "dynamicSearchWindow" : {
            "minTransitTimeCoefficient" : 0.5,
            "minWaitTimeCoefficient" : 0.5,
            "minWindow" : "1h",
            "maxWindow" : "5h"
          },
          "stopTransferCost" : {
            "DISCOURAGED" : 1500,
            "ALLOWED" : 75,
            "RECOMMENDED" : 30,
            "PREFERRED" : 0
          }
        },
        "flex": {
          "maxTransferDuration" : "5m",
          "maxFlexTripDuration" : "1h15m"
        },

        "transmodelApi": {
          "hideFeedId" : true
        }
      }
```

### Additional contract requirements

- When linking a vertex that lies inside an area, `VertexLinker.addAreaVertex()` must limit the
  number of visibility-point connections to a fixed maximum of 300, independent of how many
  visibility vertices the area contains. Linking a vertex inside an area that has more than 300
  visibility vertices must therefore create at most 300 bidirectional visibility connections
  (at most 600 area edges), in addition to the two links to the vertex itself, instead of
  connecting to every visibility vertex.
