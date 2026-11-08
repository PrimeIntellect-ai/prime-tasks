Resume option
It would be nice to have a `mailmerge --resume` option to resume sending emails in the event of a failure.

Along with this, it would makes sense to report the database row number of a sent message.  It should correspond to row number when viewing the database CSV file in a spreadsheet program.

### Additional contract requirements

- The reported number is the one-based message number: the first data record in the database CSV (the first record after the header row) is message 1, the next is message 2, and so on.  Each sent message is reported on stdout as `>>> sent message N`, where `N` is that one-based message number.
- `--resume N` starts processing at message `N` (one-based, so `--resume 1` starts at the first data record).  `--limit L` sends at most `L` messages beginning at the resume point, and `--no-limit` removes that cap.
- When processing fails on message `N`, stderr includes a hint of the form `--resume N` suggesting the value to use on the next run.
