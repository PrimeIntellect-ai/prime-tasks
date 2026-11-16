Command line tool should accept URL as input
The command line tool should accept a Mapbox Directions API request URL as input instead of a JSON file. This functionality was previously implemented in #580, which was obsoleted by #655.

/ref #476
/cc @jill-cardamon @Udumft

### Additional contract requirements

- The command line tool is invoked as `mapbox-directions-swift route <input>`, where `<input>` is a positional argument. A Mapbox Directions API request URL (for example, `https://api.mapbox.com/directions/v5/mapbox/driving-traffic/…`) is accepted as that positional argument in place of a JSON configuration file path.
- The `--input` option names a JSON file containing the API response to convert, and the `--output` option names the file to write the converted result to.
