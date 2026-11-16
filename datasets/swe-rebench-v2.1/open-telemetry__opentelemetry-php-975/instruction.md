OTLP Exporter crashing the app when getting `Export failure: Unauthorized`
**Describe your environment**

When trying out PHP OTel and Wordpress in a Docker container, while sending traces to Dynatrace, when my token was invalid, the whole wordpress container crashed.

As an OpenTelemetry user I expected the exporter to fail to export as it happens in other languages, but not crash the application.

Below is my development box and dependencies:

```
PHP 8.2.4 (cli) (built: Mar 27 2023 22:42:00) (NTS)
Copyright (c) The PHP Group
Zend Engine v4.2.4, Copyright (c) Zend Technologies
    with Zend OPcache v8.2.4, Copyright (c), by Zend Technologies
```

```php
"require": {
        "open-telemetry/api": "1.0.0beta5",
        "open-telemetry/sdk": "1.0.0beta6",
        "open-telemetry/exporter-otlp": "1.0.0beta5",
        "open-telemetry/opentelemetry-auto-wordpress": "0.0.4",
        "open-telemetry/opentelemetry-instrumentation-installer": "0.0.2",
        "guzzlehttp/guzzle": "7.4.5",
        "php-http/guzzle7-adapter": "1.0.0"
}
```

**Additional context**
Issue discussed in here: https://cloud-native.slack.com/archives/C01NFPCV44V/p1681301122955069
