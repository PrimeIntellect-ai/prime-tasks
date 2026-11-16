TwoPhotonSeries data warning
TwoPhotonSeries should not throw warning`UserWarning: missing required attribute 'data' for 'object_name' warnings.warn("missing required attribute '%s' for '%s'" % (spec.name, builder.name))` when `format='external'`

### Additional contract requirements

- `TwoPhotonSeries` is a public class in the `pynwb.ophys` module. Its constructor accepts the keyword arguments `name`, `source`, `data`, `unit`, `field_of_view`, `imaging_plane`, `pmt_gain`, `scan_line_rate`, `external_file`, `starting_frame`, `format`, and `timestamps`.
- `data` is optional: a `TwoPhotonSeries` may be created with `external_file` supplied and `data` omitted.
- `external_file` is optional: a `TwoPhotonSeries` may be created with `data` supplied and `external_file` omitted.
- If neither `data` nor `external_file` is supplied, constructing a `TwoPhotonSeries` raises a `ValueError`.
