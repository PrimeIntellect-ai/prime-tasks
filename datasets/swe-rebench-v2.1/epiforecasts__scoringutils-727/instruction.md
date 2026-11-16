`as_forecast()` should message if a forecast can be binary or point forecast
Consider the following example:

```
ex <- data.frame(
  predicted = runif(3),
  observed = runif(3),
  model = c("A", "B", "C")
) |>
  as_forecast()
```

This could in principle be a binary forecast or a point forecast. Since `observed` is not a factor, it will be classified as a point forecast. It just happened to me that I wanted to score a binary forecast, but forgot to turn it into a factor and ended up with a point forecast.
Should we message users? Maybe a message that appears once every 8 hours?
In principle all the information is there, in particular, once we have the print method ready. But on the other hand maybe it would be nice to throw an extra message.

### Additional contract requirements

When `as_forecast()` classifies input as a point forecast and all observed values are either 0 or 1, it must notify the user that the data could instead represent a binary forecast. A user-visible message or warning is sufficient; its wording need not match a particular phrase.
