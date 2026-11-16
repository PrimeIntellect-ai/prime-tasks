Parsing <input> "checked" and "value"
Parsing `<input type="checkbox" checked />` gives this warning:
You provided a `checked` prop to a form field without an `onChange` handler. This will render a read-only field. If the field should be mutable use `defaultChecked`. Otherwise, set either `onChange` or `readOnly`.


Parsning `<input type="text" value="initial value" />` gives this warning:
You provided a `value` prop to a form field without an `onChange` handler. This will render a read-only field. If the field should be mutable use `defaultValue`. Otherwise, set either `onChange` or `readOnly`.

We made an attempt to fix in the replace method:

```
[HIDDEN]
```

This seems to work, but not sure if it's the best. Maybe it would be good for support for this case in the package? I see there is something similar dom-to-react for textarea.

### Additional contract requirements

- When parsing a checkbox input with a `checked` attribute, provide `defaultChecked` rather than a controlled `checked` prop.
- When parsing a text input with a `value` attribute, provide `defaultValue` rather than a controlled `value` prop, preserving the supplied value.
