FieldSet.from_data does not accept np.datetime64 time objects
While we support `np.datetime64` throughout most of Parcels, these are not accepted in `FieldSet.from_data()` yet, which assumes that the `time` vector contains either floats or ints.
