[Bug]: Event listener on .once is called multiple times
### Describe the bug

When registering an event listener on a new consumer object using `.once()`, this listener is called multiple times.

### Your minimal, reproducible example

https://stackblitz.com/edit/nestjs-typescript-starter-agfsxk?file=src/app.controller.ts

### Steps to reproduce

Watch the console log statements.

### Expected behavior

The event listener should only be called once.

### How often does this bug happen?

Every time

### Screenshots or Videos

_No response_

### Platform

- OS: mac
- node: 16.7

### Package version

v7.0.3

### AWS SDK version

v3.316.0

### Additional context

_No response_

### Additional contract requirements

- `Consumer.on(event, listener)` and `Consumer.once(event, listener)` return the consumer instance, so that calls can be chained.
