Division by zero in src/Server.php line 175
https://github.com/reactphp/http/blob/248202e57195d06a4375f6d2f5c5b9ff9da3ea9e/src/Server.php#L175

The problem is, in Server.php at line 175 it is assumed that ```post_max_size``` will always be a set limit.

However, according to PHP manual:
```Allow unlimited post size by setting post_max_size to 0.```
https://www.php.net/manual/en/ini.core.php#ini.post-max-size

reactphp/http v0.8.6
PHP 7.1.33
