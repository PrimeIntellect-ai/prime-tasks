Exception message override log message
Hi there.


```php
try {
    throw new \RuntimeException('Not yet implemented.');
} catch (\Throwable $exception) {
    $this->logger->error('User could not be registered.', [
        'exception' => $exception,
    ]);
}
```

The above Rollbar logged event message is : `Not yet implemented`.
It should be `User could not be registered`.

### Additional contract requirements

- When a log message is supplied together with an exception, the supplied log message is used as the exception's `message` field and the exception's original message is used as the exception's `description` field.
