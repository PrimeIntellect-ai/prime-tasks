Rejection of continuous stopping in flex trips is overly strict
OTP currently rejects any flex trips have one or more stop times that contain continuous stopping values. This was originally added because the combination of flex and continuous was deemed to be invalid: https://github.com/MobilityData/gtfs-flex/issues/70

However, a closer reading of the specification shows that it's not invalid to mix them in a single trip - it's only invalid to mix them in the very same stop_time:

> `continuous_drop_off` [is] forbidden if `start_pickup_drop_off_window` or `end_pickup_drop_off_window` are defined.

https://github.com/google/transit/blob/master/gtfs/spec/en/reference.md#stop_timestxt

Reported by @m-mcqueen. cc @fpurcell.
