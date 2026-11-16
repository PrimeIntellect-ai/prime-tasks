Rotation from two vectors
[Eigen offers this function.](https://github.com/libigl/eigen/blob/master/Eigen/src/Geometry/Quaternion.h#L578)

### Additional contract requirements

Expose the operation as `axis_angle_from_two_directions(a, b)`. It computes a rotation that carries the direction of the nonzero vector `a` onto the direction of the nonzero vector `b`; the input vectors need not have unit length. Return the rotation in the repository’s axis-angle representation: an axis followed by its angle.
