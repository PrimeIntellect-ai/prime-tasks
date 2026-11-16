Rename AxisSliceInfo to SliceInfoElem
I realized that the name `AxisSliceInfo` isn't a great description for this type because it doesn't correspond to slicing information for a single input axis or a single output axis. This will be especially true if we add another variant for ellipsis-type functionality. The name `SliceInfoElem` more clearly describes the purpose of this type – to be an element in a list describing the slicing information.

I'll submit a PR after #943 is merged to avoid a merge conflict.
