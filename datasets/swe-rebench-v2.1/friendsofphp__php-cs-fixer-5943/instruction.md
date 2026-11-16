PHP 8 attributes not detected properly for no_unused_imports
## Bug report

The `no_unused_imports` fixer seems to have a problem in v3.1.0, this was possible caused by this PR https://github.com/FriendsOfPHP/PHP-CS-Fixer/pull/5720.

In v3.0.2 all classes in PHP 8 attributes would be detected, however with v3.1.0 & v3.0.3 when there are multiple attributes in one block CS Fixer will remove imports for some of the attribute classes. For example with the below code the `IsGranted` and `JsonSchema` use statements get removed using CS Fixer v3.1.0 & v3.0.3. This doesn't happen in CS Fixer v3.0.2.

   * PHP version: 8.0.8
   * PHP CS Fixer version: 3.1.0 & 3.0.3

### Config snippet
```php
$config = new PhpCsFixer\Config();
return $config
    ->setRules(array(
        '@PSR2' => true,
        '@Symfony' => true,
        'single_blank_line_before_namespace' => false,
        'phpdoc_var_without_name' => false,
        'phpdoc_summary' => false,
        'phpdoc_no_empty_return' => false,
        'blank_line_before_statement' => ['statements' => ['return']],
        'concat_space' => ['spacing' => 'one'],
        'function_typehint_space' => true,
        'no_blank_lines_after_class_opening' => true,
        'no_blank_lines_after_phpdoc' => true,
        'no_blank_lines_before_namespace' => true,
        'no_empty_comment' => true,
        'no_empty_phpdoc' => true,
        'no_empty_statement' => true,
        'no_extra_blank_lines' => true,
        'no_leading_import_slash' => true,
        'no_leading_namespace_whitespace' => true,
        'echo_tag_syntax' => ['format' => 'long'],
        'no_spaces_around_offset' => true,
        'no_unused_imports' => true,
        'no_whitespace_before_comma_in_array' => true,
        'no_whitespace_in_blank_line' => true,
        'object_operator_without_whitespace' => true,
        'phpdoc_scalar' => true,
        'phpdoc_separation' => true,
        'phpdoc_types' => true,
        'single_quote' => true,
        'standardize_not_equals' => true,
        'ternary_operator_spaces' => true,
        'trim_array_spaces' => true,
        'whitespace_after_comma_in_array' => true,
        'yoda_style' => false,
    ))
```

### Code snippet that reproduces the problem

  ```php
<?php
use Acme\JsonSchemaValidationBundle\Annotation\JsonSchema;
use Sensio\Bundle\FrameworkExtraBundle\Configuration\IsGranted;
use Symfony\Component\Routing\Annotation\Route;

...
#[
    Route('/basket/{uuid}/item', name: 'addBasketItem', requirements: ['uuid' => '%regex.uuid%'], methods: ['POST']),
    IsGranted('ROLE_USER'),
    JsonSchema('Public/Basket/addItem.json'),
]
  ```

Expected result: No code changes

Result with v3.1.0 & v3.0.3:
  ```php
<?php
use Symfony\Component\Routing\Annotation\Route;

...
#[
    Route('/basket/{uuid}/item', name: 'addBasketItem', requirements: ['uuid' => '%regex.uuid%'], methods: ['POST']),
    IsGranted('ROLE_USER'),
    JsonSchema('Public/Basket/addItem.json'),
]
  ```
