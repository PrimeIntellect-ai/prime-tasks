Human-readable memory strings in skein.Resources
What do you think about changing the constructor of `skein.Resources` to accept memory as either a number of megabytes, or a string, e.g. "5G" or "1024M"? This could be a bit more readable for bigger containers. We routinely allocate 20-30G, and 20 * 2**10 does not look as nice.

### Additional contract requirements

- Add a public function `parse_memory(s)` in module `skein.model`. It accepts a string, integer, or float representing a memory quantity and returns the number of mebibytes (MiB) as an integer, rounded up. Integers and floats are interpreted as MiB. Malformed or negative inputs raise `ValueError`; unsupported types raise `TypeError`.
- Memory strings are case-insensitive and may include units (for example `"5 GiB"`, `"100MiB"`, `"100M"`, `"KB"`). Binary prefixes `Ki`, `Mi`, `Gi`, `Ti`, `Pi` denote powers of 1024, decimal prefixes `K`, `M`, `G`, `T`, `P` denote powers of 1000, a trailing `B` is optional, and a string with no unit is interpreted as MiB.
- `parse_memory` accepts scientific-notation strings: `parse_memory('1e3')` returns `1000`, and `parse_memory('1e6 kB')` returns `math_ceil(1e6 * 1e3 / (2 ** 20))`.
- The module `skein.compatibility` exposes `math_ceil(x)`, which returns the ceiling of `x` as an integer.
- `skein.model.Resources` accepts `memory` as an integer, float, or string (strings parsed as described above) together with an integer `vcores`. Its `memory` attribute returns the normalized amount in MiB, and assigning to `memory` normalizes supported values and rejects negative values.
