Emit Telemetry Event if PUT to Status Blob Fails
There have been cases where the status blob does not exist, but we do not have telemetry to track this. Please consider sending a telemetry event if the PUT to the status blob fails.
