Current data gets scaled by I_typ
When loading in current data it gets scaled by I_typ. This is happening during `check_and_update_parameter_values` - when updating the C-rate to be the current data/capacity, the current data is also being altered
