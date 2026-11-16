Prevent Uptime Kuma from keeping previous successful messages
This is a triage of #615.

Uptime Kuma seems to have two (undesirable) behaviors: keeping the previous message or assuming the empty message means "OK" even if the status is "down". We can work around it by making sure a non-empty message is always sent when an error happens.

### Additional contract requirements

- When a failure occurs with an empty message, send the message `Failing`.
