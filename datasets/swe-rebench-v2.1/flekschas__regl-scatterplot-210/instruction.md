Split up performance mode options
Right now there is a single "performanceMode" option. This both makes the points render as squares (easier on the fragment shader), and disables blending. Our application depends on having alpha blending, but point shapes aren't nearly as important. Some of our users only have a low-tier integrated GPU and we have ~11m points, so we could greatly benefit from just having the blending instead of both blend mode and shader change. Would it be possible to separate those two?

With kind regards & thanks in advance!

### Additional contract requirements

- `renderPointsAsSquares` controls the rendered point shape. When `true`, points are rendered as squares; when `false` (the default), points are rendered as circles. Because a square covers the full point quad while a circle leaves the corners transparent, a squared point lights up more pixels than a circular point of the same size in an exported image.
- `disableAlphaBlending` controls alpha blending. When `true`, alpha blending is disabled, so overlapping semi-transparent points do not accumulate opacity; when `false` (the default), alpha blending is enabled, so overlapping semi-transparent points accumulate opacity and the total alpha of the overlap is higher.
- The two flags are independent: enabling one does not enable the other.
- Setting `performanceMode` to `true` implies both `renderPointsAsSquares` and `disableAlphaBlending` are `true`.
