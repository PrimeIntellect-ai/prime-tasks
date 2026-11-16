Support passing annotations for rules
Related: https://github.com/apache/incubator-openwhisk-cli/issues/426

I inspected the `rules` code and there doesn't seem to be any code that will pass on annotations.

Looks like [HIDDEN]:
https://github.com/apache/incubator-openwhisk-client-js/blob/e772a2fd0811f4a2c7a0cc4e832c4d08e192b320[HIDDEN]
should accept annotations in the options like [HIDDEN]:
https://github.com/apache/incubator-openwhisk-client-js/blob/e772a2fd0811f4a2c7a0cc4e832c4d08e192b320[HIDDEN]

### Additional contract requirements

- When creating a rule, callers may provide an `annotations` object in the options. Include its key/value entries in the rule definition as an annotations array of `{key, value}` objects.
