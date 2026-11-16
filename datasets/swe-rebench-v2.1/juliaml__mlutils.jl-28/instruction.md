use keyword `dims` for unsqueeze, stack, unstack

### Additional contract requirements

`unsqueeze` accepts the insertion dimension as the keyword `dims`, including when called in curried form as `unsqueeze(; dims=...)`. `stack` accepts its stacking dimension as `dims`, and the resulting array has the inputs stacked along that requested dimension. `unstack` accepts its split dimension as `dims` and returns the slices from that requested dimension.
