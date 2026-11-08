Long-running snapshot leave behind incomplete snapshots and shows 0 byte size
I have a policy that snapshots a directory daily at 4:30 am. Every day, it runs on schedule, takes around 2-3 hours, then reports that it finished. However, at that point, the snapshot size shows “0 B”, where in reality it’s around 2.2 TB. Looking at the list of snapshots for that policy, I see "incomplete" snapshots every 45 mins after the backup started (i.e. 5:15 am, 6:00 am, etc.). That makes sense, given how incomplete snapshots work ([FAQs - What are Incomplete Snapshots?](https://kopia.io/docs/faqs/#what-are-incomplete-snapshots)), but it **doesn't** make sense that they would persist after the snapshot completes.

Looking in the logs for the snapshot tasks (“Tasks” tab in UI, drill into relevant row), I don’t see any errors or indications of a problem. As far as I can tell, the snapshot does complete successfully (as such), it just doesn't clean up the incomplete snapshots. Plus it reports the size as 0 B.

The next snapshot that runs (whether manual or scheduled) cleans this up. It takes a few seconds, cleans up the incomplete snapshots, shows a full complete snapshot instead, and updates the size to show ~2.2 TB. It does **not** however actually take a new snapshot. For that reason, I was manually clicking "Snapshot Now" every day to work around this issue. Then someone on the forum suggested a second daily snapshot, and that's working for me. I have a second snapshot scheduled at 9:30 am every day, and that cleans up the 4:30 snapshot for me.

As I mentioned, I posted about this issue on the forum. There's more detail there, including screenshots.
[Daily snapshot finishes, shows 0B, retries](https://kopia.discourse.group/t/daily-snapshot-finishes-shows-0b-retries/2194)
