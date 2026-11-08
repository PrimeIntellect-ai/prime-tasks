Arithmetic operations with pf.Coordinates
It would be nice to be able to use arithmetic operations with pf.Coordinates, similar to audio objects.
ideas would be:
- [x] addition of 2 Coordinates objects
- [x] substraction of 2 Coordinates objects
- [x] dot product
- [x] cross product

### Additional contract requirements

- Support adding two `pf.Coordinates` objects and return a `pf.Coordinates` result containing their component-wise sum.
- Support subtracting two `pf.Coordinates` objects and return a `pf.Coordinates` result containing their component-wise difference.
- Make the dot product of two `pf.Coordinates` objects available through the public `pf.dot` entry point.
- Make the cross product of two `pf.Coordinates` objects available through the public `pf.cross` entry point.
