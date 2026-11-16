Unable to validate numbers using validatesFormatOf
# Description/Steps to reproduce

Create a model with a property that is a `Number` type and try to use `validatesFormatOf` to validate the format of the number. For example, try to validate that the number is a positive integer using something like this:

```javascript
return Model.validatesFormatOf('someProperty', { with: /^\+?(0|[1-9]\d*)$/ });
```
This issue was also noted in https://github.com/strongloop/loopback-datasource-juggler/issues/1355 in the past and in that it is mentioned that validatesLengthOf and validatesFormatOf accept string only. The issue was closed without any action.

I can't see a good reason why this type of validation should only work with strings. I would think it a pretty common use case to want to validate the format of numbers as well as strings.

# Expected result

As per the documentation at http://apidocs.strongloop.com/loopback-datasource-juggler/#validatable-validatesformatof I would expect this validation to work regardless of wether the property is a string or a number.
