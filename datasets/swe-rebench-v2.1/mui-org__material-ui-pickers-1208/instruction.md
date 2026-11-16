TextField props missing from TS types
# Environment

| Tech                 | Version |
| -------------------- | ------- |
| @material-ui/pickers |  3.2.0       |
| material-ui          |   3.2.0      |
| React                |    16.8.6     |
| Browser              |    Chrome     |
| Peer library         | date-fns        | <!-- date-fns, luxon or moment and version  --> |

## Steps to reproduce

1. Build a component like this:

```ts
<KeyboardDatePicker inputProps={{ 'data-testid': 'job-expire-date-input' }} />
```
2. Check it with TypeScript.

## Expected behavior

`inputProps` should be recognized as one of the TextField props that gets forwarded.

## Actual behavior

> Property 'inputProps' does not exist on type

If you're extending or inheriting the props from TextField, it should just work. I haven't dove into the code yet, but if you're not currently doing that, it may be easier than explicitly whitelisted which props are passed down.

### Additional contract requirements

- The `inputProps` prop is accepted by both the keyboard-enabled date picker (`KeyboardDatePicker`) and the non-keyboard date picker (`DatePicker`), and is forwarded unchanged to the underlying text field input.
