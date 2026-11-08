resetForm should reinitialize this.initialValues even if nextValues is not provided
## Bug, Feature, or Question?

IMO Bug ;-)

## Current Behavior

Calling `resetForm` without `nextValues` causing that `dirty` stay equal to `true`, because `this.initialValues` is not updated.

## Desired Behavior

`resetForm` should also reset `this.initialValues` so `dirty` flag will be equal to `false` after reset.

## Suggested Solutions

change this 3 lines [HIDDEN]
```
    [HIDDEN]

```
on this
```javascript
[HIDDEN]
```

### Additional contract requirements

- When `resetForm` is called without `nextValues`, it must reset the form to the current `initialValues` prop and clear the `dirty` flag.
