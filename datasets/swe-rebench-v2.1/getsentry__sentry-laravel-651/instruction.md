Adding a string with the key `user` to loging context throws an exception
### Environment

Sentry: 3.1.3
Laravel: 9.43.0

### Steps to Reproduce

1. Use sentry as the logger driver

```
        'stack' => [
            'driver' => 'stack',
            'channels' => ['daily', 'sentry'],
            'ignore_exceptions' => false,
        ],
```


2. Send a log

```
logger()->info('user', ['userId' => 5, 'user' => 'abc'])
```

### Expected Result

The log is added without any problems.

If this is expected behaviour, this should be explicitly documented somewhere

### Actual Result

An exception is thrown, b/c `user` is apparently a reserved keyword, and passing it in the log creates an exception

![image](https://user-images.githubusercontent.com/43403182/216598427-802d1912-dbe9-469d-b469-17677cd904d2.png)

### Additional contract requirements

- When the log context is `['user' => 'invalid value']`, the emitted event must include `['user' => 'invalid value']` as its `log_context` extra.
