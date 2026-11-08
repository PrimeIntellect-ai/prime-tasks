Use GAZE_COORDS instead of DISPLAY_COORDS for resolution detection
## Current Behavior

`parse_eyelink()` currently uses the `DISPLAY_COORDS` message to detect the screen resolution. This is an optional message to define the resolution for Data Viewer, and some ASC files may not contain such a message. `from_asc()` results in an error in such cases.

## Expected Behavior

The `GAZE_COORDS` should be used because (as far as I can tell) it is always logged at the beginning of a trial. Theoretically, it might be possible to use a different resolution for each trial, but I don't expect this to be common, so we could just proceed in the same way as with the sampling rate (#887), where we warn the user about inconsistent resolution settings.

## Minimum acceptance criteria

- ASC files without `DISPLAY_COORDS` message parsed correctly

### Additional contract requirements

- `parse_eyelink` returns a metadata dictionary that always contains a `resolution` key holding a tuple of two floats `(width_px, height_px)`, derived from the `GAZE_COORDS` message of each recording block.
- If a `DISPLAY_COORDS` message is present, the metadata dictionary also contains a `DISPLAY_COORDS` key holding a tuple of four floats `(left, top, right, bottom)`.
- Each entry of the returned metadata's `recording_config` list contains a `resolution` key holding a tuple of two floats `(width_px, height_px)`.
- When `GAZE_COORDS` resolutions are inconsistent across recording blocks, a warning is emitted whose message contains `Found inconsistent values for 'resolution': ` followed by the inconsistent resolution tuples as a list of float tuples.
- `from_asc` populates the experiment screen dimensions (`screen.width_px` and `screen.height_px`) from the parsed resolution.
