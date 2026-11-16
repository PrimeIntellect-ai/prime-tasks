Fire an event when the Consumer is started
As requested in this discussion:
https://github.com/bbc/sqs-consumer/discussions/387

We should fire an event when the Consumer is started, like we do when it is stopped.

https://bbc.github.io/sqs-consumer/interfaces/Events.html#stopped

### Additional contract requirements

- When the Consumer starts, it emits an event named `started`.
