Support zero-padded month numbers in SWY?
A [user on the forums](https://community.naturalcapitalproject.org/t/precipitation-data-not-red/3385/3) wanted to have their SWY month numbers zero-padded, which the model can't currently handle.

So instead of a file named `et0-1.tif`, we could also support `et0-01.tif`.

This is a really interesting idea, though, since padding single-digit months would help to keep things in lexicographic order when listing files in a directory and wouldn't be difficult to implement as an option since we're using a regular expression to find these files anyways.

### Additional contract requirements

SWY accepts monthly precipitation and evapotranspiration raster filenames with a zero-padded single-digit month number as well as filenames with an unpadded month number.
