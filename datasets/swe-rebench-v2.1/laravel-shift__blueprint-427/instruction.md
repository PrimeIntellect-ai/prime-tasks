Morphs php annotation incorrect
* Laravel Version: 8.24.0
* PHP Version: 8.0
* Blueprint Version: 1.20.2
* Platform: Mac

In yaml
```yaml
obj: morphs
```

Generated annotation in Model:
```php
/**
 * @property string $obj
 */
```

Expected:
```php
/**
 * @property int $obj_id
 * @property string $obj_type
 */
```

Didn't test morphsUuid...

### Additional contract requirements

- For `nullableMorphs`, generate `@property int|null $obj_id` and `@property string|null $obj_type`; for `uuidMorphs`, generate `@property string $obj_id` and `@property string $obj_type`; and for `nullableUuidMorphs`, generate `@property string|null $obj_id` and `@property string|null $obj_type`.
