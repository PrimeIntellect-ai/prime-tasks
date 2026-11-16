Support "secret_scanning_alert" webhooks and event payloads
Secret scanning has been GA since April 2021 (https://github.blog/changelog/2021-04-01-secret-scanning-for-private-repositories-is-generally-available/) for Advanced Security and since 3.1 in Enterprise.

The webhook payload is documented here
https://docs.github.com/en/developers/webhooks-and-events/webhooks/webhook-events-and-payloads#secret_scanning_alert

### Additional contract requirements

Expose the webhook payload through an exported Go event type named `SecretScanningAlertEvent`. An `Event` with type `SecretScanningAlertEvent` must be parseable into a value of that type, with payload fields decoded according to the documented webhook schema.
