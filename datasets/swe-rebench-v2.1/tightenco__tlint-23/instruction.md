NoStringInterpolationWithoutBraces does not trigger for object properties
Working as intended (triggers lint)
```php
echo "$a";
```

Not working as intended (does not trigger lint)
```php
echo "$object->prop";
```
