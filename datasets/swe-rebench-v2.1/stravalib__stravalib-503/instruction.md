Stravalib2.0 -> Remove BackwardCompatibilityMixin
- [x] Remove this mixin to prevent typing issues such as #437.
- [x] Remove all `_field_conversions` from model classes.

The "enhanced" fields will get the same (parent) type as the overridden fields from the generated strava model.
This will make several tests fail, which will be resolved in other issues.

### Additional contract requirements

- The fields `elapsed_time`, `moving_time` and `pr_elapsed_time` return the same type as the corresponding field in the generated Strava model, an integer number of seconds.
