average_speed was infinite error in PathDetail calculation
I am running into this error:

https://github.com/graphhopper/graphhopper/blob/e72c67d7fdad39c5cd1b3ecaeb91ec65ae5d9eb2/core/src/main/java/com/graphhopper/util/details/AverageSpeedDetails.java#L37-L41

I think the error is thrown whenever the edge distance is below a certain threshold (because then `calcMillis` will return zero). What mechanism is supposed to prevent this error ? We'd have to exclude edges below a certain distance or something (which as far as I know we do not) ?.

And another question: Why are we calculating speed=distance/time here ? Can we not just use the `averageSpeedEnc` to obtain the speed directly from the edge ?

### Additional contract requirements

- For the short-distance case with a 0.01-distance edge, `AVERAGE_SPEED` details must contain 4 entries for the path from node 1 to node 6; for the reverse path from node 6 to node 1, they must contain 5 entries, with the first detail's value null.
