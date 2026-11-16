Minimum Items validation in multiple choice inputs is not working
### Prerequisites

- [X] I have read the [documentation](https://github.com/mozilla-services/react-jsonschema-form/blob/master/README.md#readme);
- [X] In the case of a bug report, I understand that providing a [SSCCE](http://sscce.org/) example is tremendously useful to the maintainers.

### Description

I'm using an array with "ui:widget": "checkboxes" to render a checkbox group in a form, and minItems=1 to validate that the user has selected at least one item.
When a form is first rendered, we have no formData, so this is the initial state is undefined formData for the field, not an empty array.
The minItems is causing an extra 'undefined' entry to be added to the formData, which means that the validation does not work, as this entry stays here no matter what the user selects.

### Steps to Reproduce

This can be seen easily in the playground, under Arrays. Add "minItems": 1 to the multipleChoicesList section, and then delete the whole entry for multipleChoicesList from the formData section.

Now click one of the checkboxes in the live demo and see what happens to the formData. A null entry is added after the selected values. Make it "minItems": 2, delete the formData entry and try again, and 2 null entries are added. This means that the minimum items validation does not work.

I thought that I could set a default empty array for the field, by adding default: [] in the schema, but this changes the nulls to empty arrays.

#### Expected behavior

When the user has no items selected, a minimum items validation error message should be shown.

#### Actual behavior

The minimum items error is not shown.

### Version

0.44.0

### Additional contract requirements

- When initialized with `formData: {}`, a checkbox-group array named `multipleChoicesList` with `minItems: 3` must be present in form state as `multipleChoicesList: []`; with live validation enabled, the form must have one error whose name is `minItems` and argument is `3`.
- After a checkbox is selected in that group, its form-state array must contain the selected value(s) without synthetic `null` or `undefined` entries.
