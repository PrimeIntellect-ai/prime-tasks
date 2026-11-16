[BUG] Missing stack trace of thrown error in log produced by nestjs built-in error handler
<!-- Please don't delete this template or we'll close your issue -->
<!-- Before creating an issue please make sure you are using the latest version. -->

[x] I've read [the docs of nestjs-pino](https://github.com/iamolegga/nestjs-pino/blob/master/README.md)

[x] I've read [the docs of pino](https://getpino.io/#/)

[x] I couldn't find the same [open issue of nestjs-pino](https://github.com/iamolegga/nestjs-pino/issues)

There is an open issue https://github.com/iamolegga/nestjs-pino/issues/535, but that issue focuses on `express`, but I am not convinced my issue is related to `express`.

**What is the current behavior?**
`nestjs-pino@2.3.0` is missing stack traces

**What is the expected behavior?**
Stack traces should be included in error logs, just like previously in `nestjs-pino@1.4.0`

**Please provide minimal example repo. Without it this issue will be closed**
I created two NestJS applications, older one includes stack traces in error logs, newer version does not.

See examples here: https://github.com/raidokaldma/nestjs-pino-issue

### Additional contract requirements

- For a controller error handled by Nest’s built-in error handler, the log entry’s `msg` and `err.message` must equal the thrown error’s message, and `err.stack` must include the thrown error’s stack trace.
