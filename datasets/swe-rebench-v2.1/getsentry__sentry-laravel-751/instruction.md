Type mismatch for description argument when accessing files
### How do you use Sentry?

Sentry SaaS (sentry.io)

### SDK version

3.7.0

### Steps to reproduce

1. Install Sentry as per the [guide](https://docs.sentry.io/platforms/php/guides/laravel/)
2. Execute the following code

`/routes/web.php`

```php
Route::get('/', function () {
    app(\Illuminate\Filesystem\FilesystemManager::class)->disk('local')->files();
});
```

### Expected result

No error

### Actual result

```
Sentry\Laravel\Features\Storage\SentryFilesystem::withSentry(): Argument #3 ($description) must be of type string, null given, called in /tmp/tmp.WVmvUY3TWW/vendor/sentry/sentry-laravel/src/Sentry/Laravel/Features/Storage/SentryFilesystem.php on line 182
```

![20230801-1122](https://github.com/getsentry/sentry-laravel/assets/10062339/46884077-d4c3-4a09-b2ba-0614d084fd72)

### Additional contract requirements

The span operation for a filesystem call is `file.<method>` (for example, a `files()` call creates a span with operation `file.files`). This is the same value used as the breadcrumb category.
