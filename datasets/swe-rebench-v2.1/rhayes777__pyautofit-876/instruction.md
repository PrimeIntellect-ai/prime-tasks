Make Sensitivity Mapping Support serial and parallel CPU fits
Sensitivity mapping requires that `number_of_cores > 1`.

This means we cannot perform sensitivity mapping in a regime where the map is performed 1 fit at a time, but the parallelization occurs for the non-linear search.

For high memory use cases this can be a better parallelization scheme.

Can you provide support for both? The `class GridSearch` does this so I would guess a lot of functionality can be reused.

### Additional contract requirements

- The sensitivity-mapping class is `Sensitivity` in `autofit.non_linear.grid.sensitivity`. It accepts a `number_of_cores` argument and stores the supplied value unchanged on the instance as `number_of_cores`; a supplied value is never replaced by a default.
- `Sensitivity.run()` returns one result per sensitivity-map fit. If a job raises an exception, `run()` propagates that exception to the caller.
