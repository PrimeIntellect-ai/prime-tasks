Hide frame from tracebacks
Sometimes it is useful to completely omit a frame from a traceback. Suggest a local variable with a name like `_rich_traceback_omit`

### Additional contract requirements

Interpret the local `_rich_traceback_omit` variable by truthiness: any truthy value omits that frame from the traceback, while a falsey value leaves the frame in the traceback.
