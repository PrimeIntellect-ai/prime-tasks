change_scaling in ScaleAwarePointRecord changes x, y, z
When writing a script to merge multiple las files with different offsets and scales together, I noticed unexpected behaviour in the change_scaling method in `ScaleAwarePointRecord`. I had expected this would keep `x`, `y`, `z` constant but alter `X`, `Y`, `Z` and of course `scales` and `offsets`. However, this does not seem to be the case.

Digging into the source code I think the `None` check code should change from
[HIDDEN]
to
[HIDDEN]

This would also make it the pretty much the same as in `LasData`'s `change_scaling` (which presumably had the same problem until it was fixed in version 2.0.2).

### Additional contract requirements

- For `ScaleAwarePointRecord.change_scaling`, changing scales and/or offsets must preserve the scaled `x`, `y`, and `z` coordinates while updating `X`, `Y`, and `Z` to represent the requested transform.
- Any omitted scales or offsets must retain their existing values.
