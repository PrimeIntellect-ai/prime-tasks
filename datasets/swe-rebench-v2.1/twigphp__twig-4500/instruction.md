Null-coalescing does not work when method returns null
```twig
{{ something.nice(category) ?? 'nope' }}
```
should return `nope` but the result is empty

tried to add a test to `tests/IntegrationTest.php` but not sure how to inject an object for `tests/Fixtures/tests/null_coalesce.test`

this broke my code after latest release: i had a function where it accepts only string type but then the null coalesce stopped working and null was passed instead of the fallback string
