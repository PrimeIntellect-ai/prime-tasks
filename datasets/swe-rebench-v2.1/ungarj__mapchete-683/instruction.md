The extract function of a Grid can cause exception
I am using mapchete to read a data in a window from a TileDirectory.

I am using the extract function of the grid class for building a grid that I can use with mapchete.io.raster.read.read_raster_window.

However I have an exception when I call this function due to the fact that  the following line

[HIDDEN]

Second point with this class is an exception raised when the width or height is 0. It might be interesting to have a something like a minimum grid size ?

Maybe I am using an unsupported path to do what I want though.

### Additional contract requirements

- When the requested bounds lie within or along the edges of a single source pixel spanning `(0, 0, 1, 1)`, `Grid.extract` must return a grid with shape `(1, 1)` and bounds equal to `Bounds.from_inp((0, 0, 1, 1))`.
- When requested bounds produce fractional grid dimensions, `Grid.extract` must return a grid with integral row and column counts rather than fail because of those fractional dimensions.
