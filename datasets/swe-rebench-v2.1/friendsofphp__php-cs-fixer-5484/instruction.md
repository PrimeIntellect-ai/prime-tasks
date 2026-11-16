nullable_type_declaration_for_default_null_value adds ? to mixed
## Bug report

php 8.0.1
php-cs-fixer 2.18.2

```diff
-function a(mixed $val = null): void
+function a(?mixed $val = null): void
{
}
```

https://3v4l.org/Ei4aY
