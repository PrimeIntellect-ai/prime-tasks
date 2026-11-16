`floats()` does not generate subnormal floating-point values
https://github.com/HypothesisWorks/hypothesis/blob/3226dd7d1b39d5ce38d559c0c4329aca40ecc9cb/hypothesis-python/tests/nocover/test_floating.py#L107-L136

This was discovered in #2973, but out of scope for that PR.  The first step is to determine when, *if ever*, this did work; what (if anything) changed to break it, and then to get subnormal-float generation working.

### Additional contract requirements

Subnormal values were already possible outputs of the default `floats()` strategy; they were not made impossible by a regression. Their chance of occurring was negligible because they occupy only a small part of the exponent range. The requested change is to make subnormal values of both signs occur often enough to be practically discoverable through ordinary use of `floats()`.
