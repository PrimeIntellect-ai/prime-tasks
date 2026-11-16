HQ exponential decay discrepancy
James mentioned that there is a discrepancy in how exponential decay is handled between source and the UG.

What the source code is doing: `exp(-dist / max_dist)`
What the UG says it should be doing: `exp(-(2.99 / max_dist) * dist)`

This came up from https://github.com/natcap/pygeoprocessing/issues/268#issuecomment-1299358823.
