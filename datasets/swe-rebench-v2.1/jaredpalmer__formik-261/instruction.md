Warning: You should not use a non-string <Field component> and <Field children> in the same <Field> component; <Field component> will be ignored.
Using a custom Select field gives me the warning ` Warning: You should not use a non-string <Field component> and <Field children> in the same <Field> component; <Field component> will be ignored.`.

I dont' see how I can use a custom Select component on a Field, not be a string and also have children, I think this warning isn't valid.

This is the code that generates the warning.
```jsx
<Field
  component={FormikSelectField}
  name="availability"
  floatingLabelText="Availability"
  fullWidth
>
  {Object.keys(USER_AVAILABILITY_LABELS).map(availability => (
    <MenuItem
      key={availability}
      value={availability}
      primaryText={USER_AVAILABILITY_LABELS[availability]}
    />
  ))}
</Field>
```

```jsx
// FormikSelectField.js
import React from 'react';
import SelectField from 'material-ui/SelectField';

const FormikSelectField = ({
  field: { name, value },
  form: { touched, errors, setFieldValue, setFieldTouched },
  onChange,
  ...otherProps
}) => {
  const handleChange = (event, key, data) => {
    setFieldTouched(name, true);
    setFieldValue(name, data);

    if (onChange) {
      onChange(event, key, data);
    }
  };

  return (
    <SelectField
      errorText={touched[name] && errors[name]}
      value={value}
      onChange={handleChange}
      {...otherProps}
    />
  );
};

export default FormikSelectField;
```

### Additional contract requirements

`<Field>` must emit warnings (through the `warning` library) for the following invalid prop combinations, using exactly these messages:

- When both `component` and `render` are supplied:
  `You should not use <Field component> and <Field render> in the same <Field> component; <Field component> will be ignored`
- When both `component` and a function-valued `children` are supplied:
  `You should not use <Field component> and <Field children> as a function in the same <Field> component; <Field component> will be ignored.`
- When both `render` and non-empty `children` are supplied:
  `You should not use <Field render> and <Field children> in the same <Field> component; <Field children> will be ignored`

A custom (non-string) `component` paired with ordinary element `children` (for example the `<MenuItem>` elements from the report) is a valid usage and must NOT emit the `<Field component>` / `<Field children>` warning.
