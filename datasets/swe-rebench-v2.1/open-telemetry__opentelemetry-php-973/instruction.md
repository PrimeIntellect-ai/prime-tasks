RuntimeException(code: 400)
Following example https://github.com/open-telemetry/opentelemetry-php/blob/main/examples/traces/exporters/otlp_http_json.php
fails with following issue
```
[2023-04-12T12:18:06.647406+00:00] otlp-example.ERROR: Export failure {"exception":"[object] (RuntimeException(code: 400): Bad Request at /Users/pdelewski/Projects/agent-apm-php/vendor/open-telemetry/sdk/Common/Export/Http/PsrTransport.php:106
```
It seems to be related to incorrect format of `trace_id` and `span_id`
