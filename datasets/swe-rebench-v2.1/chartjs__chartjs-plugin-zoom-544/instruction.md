Errors from zero-dimension scales
Trying to pan a zero-dimension linear scale results in a `RangeError: minimumFractionDigits value is out of range` when LinearBaseScale tries to format its ticks.

This can happen a couple of ways:

* If a scale is configured with an identical `min` and `max` - that seems like a misconfiguration, but Chart.js by itself at least attempts to handle it.
* If the browser window is shrunk enough for the chart area to have 0 dimensions

The problem occurs because `panNumericalScale` calculates a `newMin` and `newMax` of NaN [here](https://github.com/chartjs/chartjs-plugin-zoom/blob/75bce9ae07e2c64e3c98094e07a786aa4288234d/src/scale.types.js#L134). This, in turn, is because [getDecimalForPixel](https://github.com/chartjs/Chart.js/blob/v3.3.2/src/core/core.scale.js#L918) (used by getValueForPixel) and [getPixelForValue](https://github.com/chartjs/Chart.js/blob/v3.3.2/src/scales/scale.linear.js#L34) return NaN for 0-dimension scales.

I started to look at changing getDecimalForPixel and getPixelForValue to not return NaN, but I'm not sure if that's correct. (It's potentially more far-reaching, and NaN is mathematically correct.) [HIDDEN] I can submit a PR for this if it seems correct.
