Revise configuration API
The configuration API will be:

```
producers: [
  name: ...
],
processors: [
  default: ...
],
batchers: [
  one_or_many: [
    batch_size: ...,
  ]
]
```

For now processors can only have one entry (like producers). `handle_message` will receive the name of the processor. `handle_batch` will continue to receive the name of the batcher. We will replace "publishers" by "batchers".

### Additional contract requirements

A processed message can be routed to a named batcher using `Broadway.Message.put_batcher/2`.

The name of the processor is passed to `handle_message/3` as its first argument, followed by the message and the context.
