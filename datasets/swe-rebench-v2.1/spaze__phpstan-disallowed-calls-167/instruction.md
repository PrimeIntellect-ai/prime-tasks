allowExceptParams fails on v2.11.3 when concatenation with object param
I had this PHPStan rule specified in my configuration:
```neon
parameters:
	disallowedFunctionCalls:
		-
			function: 'env()'
			allowIn:
				- 'src/AllowedIn.php'
			allowExceptParams:
				-
					position: 1
					name: 'key'
					value: 'SOME_ENV'
```
and it worked perfectly fine until upgrading to version v2.11.3. In the version v2.11.3 and v2.11.4 code snippet from below fails even though it shouldn't:

```php
<?php

class WithProperty {
	/** @var string */
	public string $property;
}

class Test {
	public function __construct() {
		$withProperty = new WithProperty();
		env($withProperty->property . '_OTHER');
	}
}

```
