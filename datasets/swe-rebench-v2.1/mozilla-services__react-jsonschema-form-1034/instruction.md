Form not setting default schema values when using onChange during initialisation
### Prerequisites

- [x] I have read the [documentation](https://github.com/mozilla-services/react-jsonschema-form/blob/master/README.md#readme);
- [ ] In the case of a bug report, I understand that providing a [SSCCE](http://sscce.org/) example is tremendously useful to the maintainers.

### Description

When there are defaults set in the schema such as
```
  schema: {
    title: "A registration form",
    type: "object",
    properties: {
      firstName: {
        type: "string",
        title: "First name",
        default: "Chuck",
      }
   }
}
```

the default is correctly displayed in the form (and stored internally), but if you are using the `onChange` prop on the form and using that state for say an external submission button you never receive the defaults.

An example of this is can be seen in the playground by changing `/playground/samples/simple.js` by removing `formData.firstName` and chainging the definition of the schema property to:
```
firstName: {
  type: "string",
  title: "First name",
  default: "Chuck",
},
```

The displayed form data on the page doesn't include a firstName field as the playground is using the `onChange` prop to display that value.

I think on the form component mount it should call `onChange` once mounted to ensure any consumers of the form data have the correct values.

### Additional contract requirements

When schema defaults add values to the effective form data during initialization, the form must notify the supplied `onChange` callback with that effective form data. The notification must let consumers observe the defaults that are absent from the supplied initial form data.
