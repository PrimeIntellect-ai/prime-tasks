Store variable slices
Store variable slices in the model after discretising, for easy inspection

### Additional contract requirements

After discretisation, the model exposes its retained variable slices as `model.y_slices`, keyed by the corresponding variable symbols. Each value is a list of slices locating that variable in the model state vector; slices must be retained for every discretized state variable.
