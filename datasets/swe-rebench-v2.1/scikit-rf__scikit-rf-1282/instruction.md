Network.write_touchstone() y-parameter support
**Is your feature request related to a problem? Please describe.**
I have data that I would like to write to a y1p file with the format `# MHZ Y RI R 1`. Specifically I have two arrays, frequency (float) & y-parameters (complex). I used these arrays to create a Network object, but when writing to (y1p) touchstone, it writes the s-parameters in format `# MHz S RI R 50.0` and it does not seem like there is any input in write_touchstone() to instead write y-parameters.

**Describe the solution you'd like**
Add an input in Network.write_touchstone() function for specifying Y data format instead of S.

### Additional contract requirements

`Network.write_touchstone()` accepts a keyword argument `parameter` that selects which network parameter to write. Its value is one of `"S"`, `"Y"`, `"Z"`, `"G"` or `"H"`. The file contains the selected parameter data, and the written Touchstone option line declares that same parameter, for example `# MHz Y RI R 50.0`. When `parameter` is omitted, the writer continues to write S parameters and declares S in the option line.
