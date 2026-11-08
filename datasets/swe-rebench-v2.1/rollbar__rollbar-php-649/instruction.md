New TelemetryEvent cannot handle nested array as $body argument
I'm using the newest release of the Laravel PHP package which uses the 4.1.0 version of this package. This version can result in the following error:
```
Named parameter $message overwrites previous argument {"exception":"[object] (Error(code: 0): Named parameter $message overwrites previous argument at vendor/rollbar/rollbar/src/Payload/TelemetryEvent.php:50)
```

This error is thrown if the body argument of the TelemetryEvent __construct function is a nested array. For example (when using the Laravel-Rollbar package):
```
Log::info('This throws an error', [["data" => "some data]]);
```
The error is caused by the top-level nested array. This worked before, so this is regression of functionality.

**Simple replication**
To replicate you can do the following, which is simple direct replication of what happens in the constructor of the `TelemetryEvent` class.
```
// This throws an error
$event = new TelemetryBody(...[['data' => 'some_data']]);
```

One lever higher up, there is a restriction on what is allowed in the array of the body. The following will cause an error:
```
new TelemetryEvent(
      EventType::Log,
      EventLevel::Info,
      ["0" => ["id" => "some id"], 'message' => 'test message'],
 );
```

The above is a simplification of how the TelementryEvent is used within Rollbar-Laravel package: https://github.com/rollbar/rollbar-php-laravel/blob/f430c09887d3603bcefc870fd7a9e7abcd009920/src/TelemetryListener.php#L104 which triggers this issue.
