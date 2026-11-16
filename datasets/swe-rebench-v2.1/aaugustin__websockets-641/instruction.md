Wait for connections to terminate when closing a server
[HIDDEN] This sends a close frame with code 1001 and stops processing data immediately.

It would be nicer to close connections properly with `close(1001)`and wait for a close frame from the remote endpoint.

This is a follow-up on #394.
