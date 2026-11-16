span: provide a helper to add annotations
I kindly would like to the addition of a helper method on Span, `add_annotation`

My use case is to add an annotation to the span like this
```python
with tracer.span(name='close') as span:
     if self.sock is None:
           span.add_annotation('Socket was already closed')
     else:
           span.add_annotation('Socket is still open')
           try:
                self.sock.close()
           except Exception as e:
                span.add_annotation('Encountered an exception while closing', recoverable=True, method='memcache-close'))
```

I ask because as a helper method makes it easy for annotations to be made, without having to import too much or go through all the docs.

Perhaps something that wraps `add_time_event` say:

```python
def add_annotation(self, description, **attributes):
    [HIDDEN]
```

Thank you.

### Additional contract requirements

- `Span.add_annotation(description, **attributes)` accepts a description and keyword attributes, and records an annotation with those values as a time event on the span.
- The annotation event is timestamped with the current UTC time when it is added.
