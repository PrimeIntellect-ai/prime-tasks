Errors when parsing schema with a 'format' attribute
### Prerequisites

- [ ] I have read the [documentation](https://github.com/mozilla-services/react-jsonschema-form/blob/master/README.md#readme);
- [ ] In the case of a bug report, I understand that providing a [SSCCE](http://sscce.org/) example is tremendously useful to the maintainers.

### Description
I'm facing a problem generating a form from a JSON schema.
The API that I use to generate a JSON schema from C# types adds a **format** attribute to the properties.

Example:
```
{
  "title": "SomeClass",
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "Number": {
      "type": "number",
      "format": "double"
    }
  }
}
```
Apparently `"format": "double"` doesn't allow to render a form and I'm curious if there is any way I can avoid it or let react-jsonschema ignore the attribute when parsing?

#### Expected behavior

A successfully generated react form and no errors in the output

#### Actual behavior

The following error in the output in case properties in the schema have a **format** attribute.
`
Uncaught Error: No widget "double" for type "number"
`
