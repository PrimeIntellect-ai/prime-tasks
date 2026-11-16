Project IDs should be strings
### Environment

How do you use Sentry?
Sentry SaaS (sentry.io) or self-hosted/on-premise (which version?)

Which SDK and version?
PHP

### Steps to Reproduce

https://github.com/getsentry/sentry-php/blob/ea704bbe145657a507d73cd8bf6cc017d269fffa/src/Dsn.php#L102

### Expected Result

Project IDs should be cast as strings, not int

### Actual Result

Project IDs are int in from PHP sdks

we need project ID to not be forced to an integer because its plausible we will need it to be a UUID, or we will need it to be a 64 bit int (which breaks in JS, as an example)

### Additional contract requirements

- `Sentry\Dsn::getProjectId(bool $returnAsString = false)` returns the project ID of the DSN. When called with `true`, it returns the project ID as a `string`. When called with `false` (the default), it returns the project ID as an `int` and emits a deprecation warning whose message is exactly: `Calling the method Sentry\Dsn::getProjectId() and expecting it to return an integer is deprecated since version 3.4 and will stop working in 4.0.`
- When returned as a string, a numeric project ID larger than the platform integer range retains its exact decimal digits; it must not be narrowed by integer conversion.
