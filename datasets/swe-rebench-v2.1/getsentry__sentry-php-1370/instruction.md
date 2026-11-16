Error in RequestIntegration when HTTP header name is numeric
### How do you use Sentry?

Self-hosted/on-premise

### Version

3.2.0

### Steps to Reproduce

- Use latest `sentry-laravel` @ 2.13.0.
- Send a query that use a numeric HTTP header such as `curl -v -H "123: test" https://www.example.com`
- Notice an error in PHP error log (see below).

### Expected Result

No error is produced in PHP error log.

### Actual Result

From PHP error log:
```
PHP Fatal error:  Uncaught TypeError: strtolower(): Argument #1 ($string) must be of type string, int given in /data/site/vendor/sentry/sentry/src/Integration/RequestIntegration.php:179
Stack trace:
#0 /data/site/vendor/sentry/sentry/src/Integration/RequestIntegration.php(179): strtolower(1)
#1 /data/site/vendor/sentry/sentry/src/Integration/RequestIntegration.php(157): Sentry\Integration\RequestIntegration->sanitizeHeaders(Array)
#2 /data/site/vendor/sentry/sentry/src/Integration/RequestIntegration.php(115): Sentry\Integration\RequestIntegration->processEvent(Object(Sentry\Event), Object(Sentry\Options))
#3 /data/site/vendor/sentry/sentry/src/State/Scope.php(370): Sentry\Integration\RequestIntegration->Sentry\Integration\{closure}(Object(Sentry\Event), Object(Sentry\EventHint))
#4 /data/site/vendor/sentry/sentry/src/Client.php(264): Sentry\State\Scope->applyToEvent(Object(Sentry\Event), Object(Sentry\EventHint))
#5 /data/site/vendor/sentry/sentry/src/Client.php(147): Sentry\Client->prepareEvent(Object(Sentry\Event), Object(Sentry\EventHint), Object(Sentry\State\Scope))
#6 /data/site/vendor/sentry/sentry/src/Client.php(139): Sentry\Client->captureEvent(Object(Sentry\Event), Object(Sentry\EventHint), Object(Sentry\State\Scope))
#7 /data/site/vendor/sentry/sentry/src/State/Hub.php(138): Sentry\Client->captureException(Object(TypeError), Object(Sentry\State\Scope), Object(Sentry\EventHint))
#8 /data/site/app/Exceptions/Handler.php(151): Sentry\State\Hub->captureException(Object(TypeError))
#9 /data/site/app/Exceptions/Handler.php(87): App\Exceptions\Handler->reportWithSentry(Object(TypeError))
#10 /data/site/vendor/laravel/framework/src/Illuminate/Foundation/Bootstrap/HandleExceptions.php(191): App\Exceptions\Handler->report(Object(TypeError))
#11 /data/site/vendor/laravel/framework/src/Illuminate/Foundation/Bootstrap/HandleExceptions.php(259): Illuminate\Foundation\Bootstrap\HandleExceptions->handleException(Object(TypeError))
#12 [internal function]: Illuminate\Foundation\Bootstrap\HandleExceptions->Illuminate\Foundation\Bootstrap\{closure}(Object(TypeError))
#13 {main}
  thrown in /data/site/vendor/sentry/sentry/src/Integration/RequestIntegration.php on line 179
```

### Additional contract requirements

- When a request has the header `123: test`, the captured request context must include `'123' => ['test']` in its `headers` field.
