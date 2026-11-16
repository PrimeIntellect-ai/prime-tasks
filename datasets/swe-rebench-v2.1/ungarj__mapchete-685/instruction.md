Support changing tile size in the pyramid
The tile size of the pyramid seems to be restricted to 256.

When the config is parsed a tile_size parameter for the pyramid is not taken taken but a BufferedTilePyramid can handle different size of tile_size for pyramid.

Is there a restriction to use another tile_size ?

I want to process a data set in a custom grid without reprojection, I am using a custom grid ( over EPSG:2154) but to fully handle that grid in native resolution I would need a tile_size of 1000 pixels.

### Additional contract requirements

- Provide an example configuration at `examples/custom_tile_size/custom_tile_size.mapchete`.
