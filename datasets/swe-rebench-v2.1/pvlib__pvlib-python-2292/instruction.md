snow.coverage_nrel not fully implemented according to reference
The implemented snow coverage and losses functionality refers to Ryberg and Freeman (2017) for implemented improvements to the model by Marion (2013). However Ryberg & Freeman describe a check where snow coverage is set to zero when snow cover on ground (external input data) is zero (otherwise arrays with low tilt angles are estimated to be snow covered for very lonog periods, and horizontal arrays eternally).
Since Ryberg & Freeman are referenced one could assume this functionality is implemented.

My suggestion is that either:

1. The docstring is adapted to clearly state that described functionality is not implemented.
2. This is implemented. It basically requires the input to the function to be ground snow depth rather than accumulated snow fall, along with some minor changes. (For compatibility issues the snowfall option could co-exist)

I would be able to fix this myself, but have no experience of Git/GitHub and how to contribute. If anyone can guide me I might take care of the issue - after confirmation by others?

Update Feb 19: I have given it a chance with GitHub and have forked and implemented suggestion 2. Waiting for feedback before proceeding.

### Additional contract requirements

Implement the ground-snow-depth behavior rather than resolving the issue only by changing documentation. `coverage_nrel` accepts external ground snow depth through its public `snow_depth` parameter and returns zero snow coverage at a timestep when that depth is zero. Calls that provide snowfall without ground snow depth continue to work.
