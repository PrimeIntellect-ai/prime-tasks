Child constructor should be disallowed when parent constructor is disallowed
Given code like this (this is a code from a test actually):
```php
$sub = new Inheritance\Sub();
```

and configuration (from a test as well, so no neon syntax) like:
```php
'method' => 'Inheritance\Base::__construct()',
```

the call is not reported.

The call is reported if I change the configuration to
```php
'method' => 'Inheritance\Sub::__construct()',
```

### Additional contract requirements

When a class is instantiated and the configured disallowed constructor belongs to one of its parent classes, the construction must be reported. The reported error must use the library's standard disallowed-call message format, naming the disallowed constructor and the class that is actually being constructed:

`Calling <disallowed constructor>() (as <constructed class>::__construct()) is forbidden, <configured message>`

For example, with the configuration `'method' => 'Inheritance\Base::__construct()'` and message `all your base are belong to us`, the statement `new Inheritance\Sub()` (where `Inheritance\Sub` extends `Inheritance\Base`) must be reported as:

`Calling Inheritance\Base::__construct() (as Inheritance\Sub::__construct()) is forbidden, all your base are belong to us`
