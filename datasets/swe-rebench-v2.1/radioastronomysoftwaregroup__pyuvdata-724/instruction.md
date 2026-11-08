UVCal objects don't use x_orientation properly
This occurs twice.

https://github.com/RadioAstronomySoftwareGroup/pyuvdata/blob/fb15b4a3f1546da06ba2531e04455eb3e6d9a7ea/pyuvdata/uvcal.py#L764

https://github.com/RadioAstronomySoftwareGroup/pyuvdata/blob/fb15b4a3f1546da06ba2531e04455eb3e6d9a7ea/pyuvdata/uvcal.py#L780

Both times, [HIDDEN] to allow for queries with `Jee` or `Jnn` in `get_gains()`, `get_flags()`, and `get_qualities()`.

### Additional contract requirements

String Jones labels `Jee` and `Jnn` supplied when retrieving gains, flags, or quality values must be interpreted using the UVCal object's `x_orientation` and select the corresponding stored component. The quality retrieval entry point provided by UVCal is `get_quality()`.
