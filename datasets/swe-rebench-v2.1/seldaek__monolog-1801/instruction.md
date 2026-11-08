FingersCrossedHandler Does not check passthruLevel properly
Monolog version 3.2.1

FingersCrossedHandler have an option to passthrough log line above certain level without writing out every other lines in the request.
The filtering logic check each buffered log line if it is above or equals to the passthrough level threshold.

The level has been changed to enum, which means a simple more-than comparison will no longer work.
https://github.com/Seldaek/monolog/blob/b05bf55097060ec20f49ccec0cf2f8e5aaa468b3/src/Monolog/Handler/FingersCrossedHandler.php#L185-L187
[HIDDEN]

We should also update test to cover this case.
https://github.com/Seldaek/monolog/blob/b05bf55097060ec20f49ccec0cf2f8e5aaa468b3/tests/Monolog/Handler/FingersCrossedHandlerTest.php#L253-L265

### Additional contract requirements

- When `passthruLevel` is configured, records at or above that threshold must be passed through while buffering, and records below it must not. This comparison must work with enum-based log levels.
