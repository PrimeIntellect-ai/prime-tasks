Omitting `items` from arrays causes it to throw.
### Prerequisites

- [x] I have read the [documentation](https://github.com/mozilla-services/react-jsonschema-form/blob/master/README.md#readme);
- [x] In the case of a bug report, I understand that providing a [SSCCE](http://sscce.org/) example is tremendously useful to the maintainers.

### Description

An array without the `items` field, breaks the rendered form.

I noticed some schemas I have were breaking stuff heavily in the app I'm working on. And I noticed sending invalid schemas usually results in a proper message like "the schema is invalid" or something, instead of rendering the form, but for some schemas it would just break catastrophically impacting in my whole page some times.

Upon further investigation I noticed some of my schemas had properties of type "array" with no "items" field. And I was surprised to see that in my database because I validate everything before saving. Turns out these are actually valid schemas:

>"Omitting this keyword has the same behavior as an empty schema."
http://json-schema.org/latest/json-schema-validation.html#rfc.section.6.9

[HIDDEN]

### Steps to Reproduce

1. Just run this fiddle https://jsfiddle.net/h6fsjLhj/

#### Expected behavior

I know it's probably not possible to render a form for this scenario, but the tool should ignore fields like this or probably provide feedback that this type of schema is not supported.

#### Actual behavior

The tool just throws, and since catching rendering exceptions in React is not always simple, it can cause unexpected behavior in the whole app.

### Version

0.49.0

Thanks! And let me know if I can provide more info, or if there is a workaround I can use.

### Additional contract requirements

- When an array schema is missing `items`, the rendered warning must include the exact text `Missing items definition`.
- When a schema declares a field type the form does not support, the rendered warning must include the exact text `Unknown field type <type>`, where `<type>` is the declared type.
- The warning for an unsupported schema is rendered in an element with CSS class `unsupported-field`.
