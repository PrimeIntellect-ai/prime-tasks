[FEATURE] Allow retry_login_interval to set to -1 to retry login only once and exit
Thanks again for the great work.

The way I use this container is that I run it once daily. Instead of setting the `sync_interval` to 86400, I set it to -1 so that it starts the container, runs a single sync, and then exits. This allows me to wrap it in some reporting and I don't have to worry about timing gradually shifting over time.

However, every so often the iCloud needs a new authentication code. And when that fails, the container does not exit. I know when this happens because my phone gets the Apple authentication messages. So I'm wondering: can I get the container to exit after just a single retry? Perhaps by setting `retry_login_interval` to -1, not something I see in the documentation?

### Additional contract requirements

- Setting `retry_login_interval` to a negative value (for example `-1`) makes the synchronization exit after a single login attempt instead of retrying.
- When exiting because `retry_login_interval` is negative, an informational message containing `retry_login_interval is < 0, exiting ...` is logged.


- - When login requires 2FA, the logs include `2FA is required` and contain more than one log record.
- - When synchronization exits because `retry_login_interval` is negative, `sync.sync()` returns `None`.
