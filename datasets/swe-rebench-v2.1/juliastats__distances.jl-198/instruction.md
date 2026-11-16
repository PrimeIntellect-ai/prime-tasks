Spherical angle distance
I often work with points on a sphere and need to compute distances between them. In principle, this should be covered by the `Haversine` distance in `Distances.jl`.
However, it performs multiple conversions on the way, which (slightly) affect performance and introduce extra consfusion. Namely, `Haversine` first converts inputs from degrees to radians, and then converts output from radians to linear distance units by multiplying by the radius.
So, I implemented a simple modification of that: `SphericalAngle` distance where all values are in the same units, in radians. I've been using this for quite some time already and put into my utility package. The code is available at https://gist.github.com/aplavin/6d6df09d9f17d19c70fd91ee07045a51. I think it is useful in any cases when points represent directions, do not lie on any specific sphere, and one works in natural units (radians).
If you think it can be included into `Distances.jl`, I can make a PR.

### Additional contract requirements

- Provide a lowercase convenience function `spherical_angle(x, y)` that accepts length-2 points whose coordinates are longitude and latitude in radians and returns their spherical-angle distance in radians. It should accept iterables such as vectors, tuples, and iterators, and throw `ArgumentError` if either input does not have length 2.
