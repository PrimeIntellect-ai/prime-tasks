Fatal error: Cannot redeclare humbug_phpscoper_expose_class()
## Bug report

| Question    | Answer
| ------------| ---------------
| PHP-Scoper version | 0.18.1 |
| PHP version | 8.1 |
| Platform with version | MacOS 13 |
| Github Repo | https://github.com/leoloso/PoP |


I'm using PHP-Scoper to scope 2 WordPress plugins. When I install both of them on the same site, I get the following error:

```
Fatal error: Cannot redeclare humbug_phpscoper_expose_class() (previously declared in /app/wordpress/wp-content/plugins/graphql-api/vendor/scoper-autoload.php:23) in /app/wordpress/wp-content/plugins/graphql-api-pro/vendor/scoper-autoload.php on line 27
```

The reason is clear: both plugins define function `humbug_phpscoper_expose_class` in the global space.

[HIDDEN]

For reference, this is [one of my `scoper.inc.php`](https://github.com/leoloso/PoP/blob/1a7cda04a30e4426fd34516788f8155c7f16849f/ci/scoping/scoper-graphql-api.inc.php).

### Additional contract requirements

- Generated autoload files must be safe to load alongside other generated autoload files that define the global `humbug_phpscoper_expose_class` helper; loading multiple such files must not cause a fatal function redeclaration.
