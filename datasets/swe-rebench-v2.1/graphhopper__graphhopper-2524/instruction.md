Max speed can get exceeded due to rounding error
For example `FootFlagEncoder` has a maximum speed of 15km/h. When we store the speed it is converted to an int using `speedFactor`. However, with our current logic it can happen that we set the speed to `15`, but `get(averageSpeedEnc)` returns e.g. `16`. This way the speed of an edge can exceed the maximum even when we did not exceed the maximum speed when we set the value.

This obviously can be problematic when routing with AStar, but also it can result in a 'max speed violated' error in `CustomWeighting`. See the tests here: https://github.com/graphhopper/graphhopper/commit/944d95ae5e0553e9fa74a758ae2ba17cd6d1da8e

[HIDDEN]

In the example above the speed factor is 2, so 15/2=7.5 -> round: 8 -> (int) 8, and when later it is multiplied with the factor again we get 16 > 15. Rounding might be the right thing to do for the decimal encoded value, but in the context of the flag encoder's max speed we somehow have to make sure that the maximum speed is definitely never exceeded.

Btw currently we can even do something like:
```java
edge.set(encoder.getAverageSpeedEnc(), encoder.getMaxSpeed() * 2);
```
without getting an error. But this is maybe for another issue. The main issue here is that we get back a value that exceeds the max speed even when the value we set was within the valid bounds.

Note that the failing tests are *slightly* artificial, because they deliberately use the `FootFlagEncoder`, because it has an uneven maxSpeed (15) *and* set a non-default speed factor (2 instead of 1).

### Additional contract requirements

- For every flag-encoder configuration, storing a speed at or below the encoder's reported maximum and reading it back must not produce a decoded speed above that maximum, including when the configured speed factor rounds the stored value upward.
