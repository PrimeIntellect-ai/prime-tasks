Fix DeleteSnapshot retry logic
Right now, the retry logic for the delete snapshot is handled by the `safe_to_snap` function.

Unfortunately, this function only checks if a snapshot is `IN_PROGRESS`. There are other problems (e.g. if a snapshot is being deleted) that are not handled by this method and that should be retried as well.
