allow custom widget for oneOf / anyOf select
### Prerequisites

- [x] I have read the [documentation](https://react-jsonschema-form.readthedocs.io/);
- [ ] In the case of a bug report, I understand that providing a [SSCCE](http://sscce.org/) example is tremendously useful to the maintainers.
- [ ] Ideally, I'm providing a [sample JSFiddle](https://jsfiddle.net/n1k0/f2y3fq7L/6/) or a [shared playground link](https://mozilla-services.github.io/react-jsonschema-form/) demonstrating the issue.

### Description

When providing a custom select widget, I expected it to be used for the oneOf / anyOf select. The MultiSchemaField component just renders a `select` instead of looking up the select widget ([link](https://github.com/mozilla-services/react-jsonschema-form/blob/d9bcf1acfa3fd15814654129054b3c65501f5271/src/components/fields/MultiSchemaField.js#L160)).

### Steps to Reproduce

1. Create a schema with a oneOf / anyOf property
2. Create a custom select widget and pass to the form: `<Form widgets={{ SelectWidget: MyCustomSelect }} />`
3. Observe that the select used for the oneOf / anyOf does not render the custom widget.

#### Expected behavior

I would expect that my custom widget would be rendered instead.

#### Actual behavior

A `select` element is used.

### Version

1.3.0

### Additional contract requirements

- The custom widget is supplied under the `SelectWidget` key of the `widgets` prop passed to the top-level form component.
- The custom widget receives the following props:
  - `id`: a string identifier for the selector.
  - `schema`: the selector's schema, always `{ type: "number", default: 0 }`.
  - `value`: the numeric index of the currently selected option.
  - `onChange`: a function that is called with the new numeric option index when the selection changes.
  - `options`: an object containing `enumOptions`, an array of `{ label, value }` objects, one per selectable option, where `value` is the option's numeric index.
