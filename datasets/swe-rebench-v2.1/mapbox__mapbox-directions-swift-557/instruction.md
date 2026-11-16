RouteOptions.alleyPriority, walkwayPriority, speed should be optional
`RouteOptions.alleyPriority`, `walkwayPriority`, and `speed` should be optional, and `RouteOptions.urlQueryItems` should add the corresponding URL query items if and only if these properties are non-nil.

## Problem

RouteOptions only adds the `alley_bias` parameter to the request URL if the profile is either `mapbox/driving` or `mapbox/walking`, but not for other profiles such as `mapbox/driving-traffic` that also support this parameter.

https://github.com/mapbox/mapbox-directions-swift/blob/2d9edcedef9506546fa390c8f7f10de848b2aec2/Sources/MapboxDirections/RouteOptions.swift#L191-L193

## Background

These options are limited to Valhalla-powered profiles and are unsupported in OSRM-based profiles, such as `mapbox/cycling` and formerly `mapbox/driving-traffic`. OSRM-based endpoints return an HTTP 422 error upon encountering a parameter that’s supported by Valhalla but not OSRM.

Originally, in #370, this library had to conditionalize the `alley_bias` parameter on the `mapbox/walking` profile because it’s supported by Valhalla but not OSRM. #416 later extended the parameter to the `mapbox/driving` profile once it migrated to Valhalla. We could conditionalize other parameters on the presence or absence of an explicit value, but `RouteOptions.alleyPriority` had to be non-optional because optional primitive types don’t bridge to Objective-C. Fortunately, #382 dropped Objective-C support; since then, we generally use optional types to represent incremental additions to the Directions and Map Matching APIs, even for primitive types.

## Solution

`RouteOptions.alleyPriority` should become optional, because this library still supports at least one profile (`mapbox/cycling`) that doesn’t support `alley_bias`. `RouteOptions.urlQueryItems` can thus conditionalize the addition of `alley_bias` on whether `RouteOptions.alleyPriority` is non-nil.

The `walkway_bias` and `walking_speed` parameters added in #370 are in the same situation, so `RouteOptions.walkwayPriority` and `speed` should get the same treatment. It would be pretty unlikely for a driving profile to support options specific to walkways, but `DirectionsProfileIdentifier` is an extensible enumeration and there could always be a walking-related profile other than `mapbox/walking`.

/cc @mapbox/navigation-ios @danpat @OttyLab
