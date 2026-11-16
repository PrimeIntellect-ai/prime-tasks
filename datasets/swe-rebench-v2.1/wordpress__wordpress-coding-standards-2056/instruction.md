WordPress.NamingConventions.ValidHookName.NotLowercase does not distinguish string literals from function calls
<!--
PLEASE FILL OUT THE TEMPLATE COMPLETELY.
BUG REPORTS WHICH CANNOT BE REPRODUCED BASED ON THE INFORMATION PROVIDED WILL BE CLOSED.
-->

## Bug Description
<!--
Please provide a clear and concise description of what the bug is.

What did you expect to happen? What actually happened?
-->

The `WordPress.NamingConventions.ValidHookName.NotLowercase` sniff violation is triggered when the first argument of `apply_filters` is a function call containing an argument that's not entirely lowercase, instead of validating on the return value of the function call:

```
  31 | ERROR   | [ ] Hook names should be lowercase. Expected: Filters::getBlockFilterName('form', 'datatypeselector'), but found: Filters::getBlockFilterName('form', 'dataTypeSelector').
```


## Minimal Code Snippet
<!-- Please provide example code that allows us to reproduce the issue. Do NOT paste screenshots of code! -->

The issue happens when running this command:
```bash
 php ./vendor/squizlabs/php_codesniffer/bin/phpcs --standard=WordPress form.php
```

... over a file containing this code:
```php
$formDataTypeSelector = apply_filters(
	Filters::getBlockFilterName('form', 'dataTypeSelector'),
	Components::checkAttr('formDataTypeSelector', $attributes, $manifest),
	$attributes
);
```

Important to note that the return value of the `Filters::getBlockFilterName('form', 'dataTypeSelector')` method call is `es_forms_block_form_data_type_selector`, which is entirely lowercase.

## Error Code
<!--
The error code for the sniff that is (or should be) being triggered (you
can see the sniff error codes by running `phpcs` with the `-s` flag).
e.g. `WordPress.PHP.NoSilencedErrors.Discouraged`

You can leave this section empty if you are reporting a false negative.
-->

`WordPress.NamingConventions.ValidHookName.NotLowercase`

## Environment
<!--
To find out the versions used:
* PHP: run `php -v`.
* PHPCS: run `[vendor/bin/]phpcs --version`
* WPCS: run `composer [global] info` for a Composer install.
-->

| Question               | Answer
| ------------------------| -------
| PHP version             | 7.4.29
| PHP_CodeSniffer version | 3.6.2
| WPCS version            | 2.3.0
| WPCS install type       | Composer local install as a dependency of Eightshift Coding Standards



## Additional Context (optional)
<!-- Add any other context about the problem here. -->

## Tested Against `develop` branch?
- [ ] I have verified the issue still exists in the `develop` branch of WPCS.
