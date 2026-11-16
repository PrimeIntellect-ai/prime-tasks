Generate method does not detect static contexts
That setup:
```php
	public static function setUpBeforeClass(): void
	{
		<>
		... some code ...
		<>
	}
```
should generate a static method, not an instance one.

### Additional contract requirements

- In the tested static-context case, replace the selected code with `$car = $this->newMethod($union);` while generating the static method.
