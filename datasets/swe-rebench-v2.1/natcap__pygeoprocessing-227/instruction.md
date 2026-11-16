Handle malformed keys in shapely_geom_to_vector
This issue stems from InVEST issue: https://github.com/natcap/invest/issues/545. A bad key was passed in with the attribute list which caused unhelpful `ERROR 1: Invalid index : -1` to appear.

Proposed solution:
Check to make sure the keys in the attribute list match the field name and raise a helpful ValueError if not.

T.E. 1-3 hours
