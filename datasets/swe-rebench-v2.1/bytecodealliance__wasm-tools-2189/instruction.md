Internal error involving task.return + stream type
The following wast:
```wast
(component
  (canon task.return (result (stream u8)) (core func))
)
```
fails with the following error:
```
internal error: entered unreachable code: should be expanded by now
```
This following wast succeeds, so the issue seems to be related to the `stream` in the type:
```wast
(component
  (canon task.return (result u8) (core func))
)
```

### Additional contract requirements

- When printed, the component above must produce exactly:
```wast
(component
  (type (;0;) (stream u8))
  (core func (;0;) (canon task.return (result 0)))
)
```
