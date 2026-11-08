Redefine score curves with p90 rather than podr
It's come up a few times.. most recently here https://github.com/GoogleChrome/lighthouse/pull/10495#discussion_r396711449

> we should really consider reworking our math so we can define in terms of the 90 cutoff :) haha

It makes sense, since 90 is passing and a key threshold. Our source of truth should use them instead of numbers SO CLOSE to it.

### Additional contract requirements

- A public function `getLogNormalScore(parameters, value)` in `lighthouse-core/lib/statistics.js`, where `parameters` is `{median: number, p10: number}` and `value` is a number. It returns a number in the range [0, 1] representing the proportion of the distribution greater than `value`, with `median` as the 50% point (score 0.5) and `p10` as the 10% point (score 0.9). It returns 1 for non-positive `value`, and throws when `median` is not greater than zero, when `p10` is not greater than zero, or when `p10` is not less than `median`.
- `Audit.computeLogNormalScore(controlPoints, value)` is a static method on the `Audit` class in `lighthouse-core/audits/audit.js`, where `controlPoints` is `{median: number, p10: number}` and `value` is a number. It returns the score rounded and clamped to two decimal places, returning 1 for non-positive values. It returns 0 when the unrounded score rounds to 0.00 at two decimal places; there is no separate hard cutoff. Existing audit scoring curves retain their prior behavior while using percentile-10 control points; cumulative layout shift uses p10 = 0.1.
- `getLogNormalDistribution(median, falloff)` in `lighthouse-core/lib/statistics.js` returns an object with a `computeComplementaryPercentile(value)` method that returns the proportion of the distribution above `value`.
