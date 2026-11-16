Implement a history fixing routine for unattached segment times
When you have segment time history elements that don't correspond to attempt history elements, through possibly manual modification of the split file, then the original LiveSplit just outright crashes in various ways, while livesplit-core seems to just overwrite the existing segment history elements when doing new attempts. Both seem suboptimal. There should probably be a fixing step that modifies the attempt index of the segment history elements with a new negative index.

This should be backported to the original LiveSplit.

https://splits.io/4of2

### Additional contract requirements

- This task concerns the behavior in LiveSplit Core; it does not require changes to the original LiveSplit application.

- The new index assigned to an unattached segment history element is a synthetic, non-positive index (i.e. `<= 0`). Index `0` is a valid synthetic index. When several unattached elements need to be reattached, they receive distinct non-positive indices.
- `Run::fix_splits` performs this reattachment: after it runs, no segment history element keeps an index that is greater than the maximum index in the attempt history. The reattached elements are moved to synthetic indices, while the segment history elements that still correspond to attempt history elements are left untouched.
- Reindexing an unattached segment history entry preserves its associated segment time.
