RANSAC channel picks differ between MATLAB PREP and PyPREP using the same seed
When RANSAC does its random channel selection, the random channel choices diverge between MATLAB PREP and PyPREP, even when using the same seed. This isn't super-surprising since they're different languages with different randomization functions, but it would be handy if we could PyPREP to make the same picks as MatPREP given the same seed.

In my preliminary efforts looking into this, I've learned a few things:

- Most importantly, Numpy offers an identical implementation of the "twister" randomization algorithm to MATLAB such that they should be able to produce identical random results given the same seed
- MATLAB PREP implements its own custom `randsample` function for selecting subsets of channels without replacement. If I re-implement the same logic in Python I identical results.
- MATLAB PREP also has a `getRandomSubsets` function that calls the above `randsample` function and produces different numbers yet again. Haven't tried re-implementing it in Python yet, but hopefully it's trivial!

With some luck I'll have a PR for this shortly. It's going to break seed compatibility with earlier PyPREP versions, but I think we've already done that since last release in #43.

### Additional contract requirements

- `pyprep.utils._get_random_subset(x, size, rand_state)` must accept `x` as either a Python `list` or a one-dimensional `numpy.ndarray`; both input types must be supported.
- It must return a `list` of the sampled items, drawn without replacement, in the order they are drawn.
- The sampling must reproduce MATLAB PREP's `randsample` behavior. Concretely, with `rand_state = numpy.random.RandomState(435656)`, `x = list(range(1, 61))` (or the equivalent one-dimensional array), and `size = 8`, the returned list must be `[6, 47, 55, 31, 29, 44, 36, 15]`.
- `size` is an integer no greater than `len(x)`, and `rand_state` is a `numpy.random.RandomState` controlling the deterministic draws.
