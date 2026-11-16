Remove most required properties from `add_electrode`
This is linked to https://github.com/NeurodataWithoutBorders/nwb-schema/issues/505.

The idea is to remove all the required properties but group and location from the `add_electrode` function:

- x
- y
- z
- imp
- location
- filtering
- group

The logic and background of the request is described in the linked issue above.
