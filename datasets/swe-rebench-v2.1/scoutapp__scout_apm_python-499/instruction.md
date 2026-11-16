Hide scout message about event draining
When `log_level` is set to `ERROR` and logs are redirected to a log file through `log_file_path`, scout still logs a message like: `Scout draining 1 event for up to 2.0 seconds` on STDOUT, is it possible to remove this message from STDOUT?
Thank you!

### Additional contract requirements

- Add a configuration option `shutdown_message_enabled` (boolean). It defaults to
  `True`. When it is `True`, the shutdown drain message ("Scout draining ...") is
  printed to stderr; when it is `False`, that message is not printed.
- `shutdown()` returns `None`.
- `ScoutConfig.set()` returns `None`.
