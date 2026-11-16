Support for object return types
A rule map containing more than 1 key should count as a primitive value and be returned by calling `Apply`. However, this is not currently the case in this package. Instead, any instance of a map parsed through recursive `apply` calls will continue to recurse until a primitive value is parsed and returned.  An example of this case:

Rule:
```json
{"if":[
	{"==":[{"var":"foo"},"bar"]},{"foo":"is_bar","path":"foo_is_bar"},
	{"foo":"not_bar","path":"default_object"}
]}
```

Data:

```json
{"foo": "bar"}
```

The expected return value here is the full object `{"foo":"is_bar","path":"foo_is_bar"}` which is the case in the jsonlogic playground: https://jsonlogic.com/play.html

However, this currently is parsed to a boolean value `true`
