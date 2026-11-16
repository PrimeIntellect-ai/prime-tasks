Issues with time calculation.
I think the routing algorithms do not properly calculate the times when turn costs are involved. I identified three problems:

- [x] The turn cost time is not contributing enough to the traveling time, for example for a 100m edge setting the turncosts to 2 increases the weight from 18s to 20s while the time is only increased from 18s to 18.002s. Fixed in #1586.

- [x] edge-based CH does not include the turn cost times in the calculated time at all. Everything is fine for the weight calculation and when using the fastest weighting the fastest route will be found with respect to turn costs, but `Path.getTime()` will not include the turn cost times. This has to be adjusted in `Path4CH`. Fixed in #1611.

- [x] The bidirectional algorithms (dijkstra&astar, probably also ALT) do not pay attention to turn costs at the meeting point of fwd&bwd search (the turn costs are properly included for the weight calculation, but the turn cost *time* is not added when unpacking the path. Fixed in #1586.

- [ ] `TurnWeighting` does not include default u-turn cost in `calcMillis`.

For turn *restrictions* (infinite not finite turn costs) this issue is not important, because restricted turns will not be used anyway.

See this test: 44f5c068d4e672dd905ee0b55bc5bd5095c30991
