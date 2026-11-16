Addition of a Spherical Ellipsoid
Hi,

In my field (satellite communications) it is often assumed for many simulations that the earth is just a sphere as it simplifies a lot of the computations and most of the time does not impact significantly the results.

While I do believe the simplification are not really meaningful when a proper and optimized implementation of the computation is in place (like in this ecosystem), it is still often the case that one has to simulate things with a spherical ellipsoid to reproduce results done by other with less powerful means :D.

Would you be willing to add a spherical ellipsoid (I was thinking with 6371km of radius as that is the [wikipedia](https://en.wikipedia.org/wiki/Earth_radius#:~:text=Approximating%20the%20figure%20of%20Earth,polar%20radius%2C%20denoted%20b) _average_ value), or do you think this is not meant for CoordRefSystem and should live in my private package?

I am fine with either but I believe it might be of use to someone else to have a common definition of the spherical ellipsoid living in this repository.

In case you'd be willing to have this here, what would be the most idiomatic way to define the corresponding Datum to use for the various coordinates?
Would it still be fine to have something like `Spherical6371🌎` and just `Spherical6371` for the datum? (I assume simply `Spherical` is used already for the coordinates and even if its not it would be too generic for something so niche most likely)

### Additional contract requirements

- Provide `CoordRefSystems.GRS80S🌎` as a spherical ellipsoid with equal major and minor axes and a radius of about 6,371 km.
- Provide `GRS80S` as the corresponding datum, with `ellipsoid(GRS80S)` returning `CoordRefSystems.GRS80S🌎`.
