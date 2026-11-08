Add Value.IsXxx
`Value` has several methods to cast value to specific type:

* Object
* Array
* String
* Number
* Boolean

Each of them checks that the value has correct type and returns a new object for the value.

For each of these methods, we should add a counterpart method `IsXxx` (e.g. IsObject for Object) which just checks that the value has specific type, but does not create a new object, but instead returns the original (receiver) object.

New methods should have documentation comments and unit tests.

Related: https://github.com/gavv/httpexpect/issues/252
