[Laravel Horizion] Breadcrumbs in Job handle function do not get recorded.
### Environment

Laravel: v9.44.0
Sentry: 3.12.0
Laravel-Sentry: 3.1.2
Sentry-SDK: 3.3.0

### Steps to Reproduce

Create a breadcrumb inside a job’s `handle` function.
```
\Sentry\Laravel\Integration::addBreadcrumb(new \Sentry\Breadcrumb(
    $level,
    $type,
    $category,
    $message,
    $data
));
```

Throw an exception inside the job’s `handle` function.

### Expected Result

Being able to see the breadcrumb inside the issue on Sentry.

### Actual Result

The breadcrumb does not appear.
