Output new snapshot ID whenever a command causes an existing ID to change
Output of `restic version`
--------------------------

restic 0.17.1 compiled with go1.23.1 on linux/amd64

What should restic do differently? Which functionality do you think we should add?
----------------------------------------------------------------------------------

For example when adding tags to a snapshot, it would be helpful if the output returned the resulting new snapshot ID.

What are you trying to do? What problem would this solve?
---------------------------------------------------------

Finding the same snapshot again after its ID has changed. Having to list snapshots again to find the new ID, and potentially having to compare using other metadata fields to try to ensure that it's the same one.

Sometimes one might make a note of a specific ID because the snapshot was created for a specific purpose (eg: before an upgrade), or because it was determined to be the one needed out of a set of older ones. (Yes, one could also use tags to mark these, but that's not really the point.)

Perhaps it would also be possible to (optionally) list all previous IDs, although I think only the most recent previous one is recorded.

Did restic help you today? Did it make you happy in any way?
------------------------------------------------------------

It makes me happy every time it Just Works™, which is almost always.

### Additional contract requirements

- The `restic tag` command reports, for every snapshot whose ID changes, both the
  previous snapshot ID and the resulting new snapshot ID.
- When JSON output is requested (`--json`), the command emits one JSON object per
  changed snapshot with `message_type` set to `"changed"`, `old_snapshot_id` set to
  the previous snapshot ID and `new_snapshot_id` set to the resulting snapshot ID.
  After all snapshots have been processed it emits a summary JSON object with
  `message_type` set to `"summary"` and `changed_snapshots` set to the number of
  changed snapshots.
