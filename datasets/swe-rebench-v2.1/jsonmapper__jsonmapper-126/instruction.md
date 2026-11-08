PropertyMapper cannot map with array in phpdoc
**Describe the bug**
I have a property like this:
```php```
    /** @var string|string[] */
    public $value;
```php```

The PropertyMapper [HIDDEN]
If I have a valid empty array the PropertyMapper [HIDDEN] throws an error.

I use "(new JsonMapperFactory())->bestFit()" with PHP 7.4

### Additional contract requirements

- Mapping an empty array to a property documented as `string|string[]` must succeed and leave the property as an empty array.
