Incident impact should be an enumeration
`Incident.impact` is currently decoded as a string, but [this documentation](https://docs.mapbox.com/api/navigation/directions/#incident-object) states that the `impact` may only be one of five values, so it should be decoded as an enumeration instead.

/ref #482
/cc @mapbox/navigation-ios
