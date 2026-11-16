Add option to allow snapping a waypoint to a closed road
`Waypoint` should have a `allowsSnappingToClosedRoad` property, defaulting to `false`, that corresponds to the [`snapping_include_closures`](https://docs.mapbox.com/api/navigation/directions/#optional-parameters-for-the-mapboxdriving-traffic-profile) query parameter in the Directions API. When forming a request URL, `DirectionsOptions.urlQueryItems` should map the waypoints to a semicolon-delimited list of values to set on `snapping_include_closures` as long as any of the values is `true`.

`snapping_include_closures` is currently available on the `mapbox/driving-traffic` profile, but in principle other profiles could support it in the future, so we shouldn’t limit it to that profile on the client side. I suppose technically `allowsSnappingToClosure` would make this property flexible enough to make sense for walking and cycling, but “closure” has other meanings in Swift that could confuse developers.

/cc @mapbox/navigation-ios

### Additional contract requirements

- When only the middle of three waypoints allows snapping, the `snapping_include_closures` value must be `;true;`.
- When no waypoint allows snapping (every `allowsSnappingToClosedRoad` value is `false`), the `snapping_include_closures` query parameter is omitted entirely.
- If any waypoint allows snapping, its value is serialized regardless of the selected routing profile.
