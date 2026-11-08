Align the exception raised from Harness when a service does not exist
Basically, we want to [fix this TODO](https://github.com/canonical/operator/blob/449793f9867eba11dc2e7e1c28ea3dca1e1da231/ops/testing.py#L3123) (and the related following ones).

When starting, stopping, restarting a service, if the service does not exist, then Harness will raise a `RuntimeError`, but if this happens outside of tests, then `ops.pebble.APIError` will be raised.

It's better if the Harness exceptions match the ones you normally get, so that the charm doesn't have to catch exceptions just to make test behaviour match the normal behaviour.

Note that Scenario also uses the ops.testing Pebble client, so this will also adjust Scenario as well.
