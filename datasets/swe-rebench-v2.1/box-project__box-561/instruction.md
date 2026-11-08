memory_to_bytes() INI parsing issue (32bit)
## Bug report

| Question    | Answer
| ------------| ---------------
| Box version | Box version 3.13.0@275b091
| PHP version | PHP 7.4.18 (cli) (built: Apr 27 2021 17:19:39) ( ZTS Visual C++ 2017 x86 )
| Platform with version | Windows 10
| Github Repo | NA

To replicate:
Run **box.phar compile** with [**2G**](https://www.php.net/manual/en/faq.using.php#faq.using.shorthandbytes) as PHP [memory_limit](https://www.php.net/manual/en/ini.core.php#ini.memory-limit) INI setting.

Error:

PHP Fatal error:  Uncaught TypeError: Return value of _HumbugBox113887eee2b6\KevinGH\Box\memory_to_bytes() must be of the type int, float returned in phar://box.phar/src/functions.php:81
Stack trace:
0 phar://box.phar/src/Console/Php/PhpSettingsHandler.php(62): _HumbugBox113887eee2b6\KevinGH\Box\memory_to_bytes('2G')
1 phar://box.phar/src/Console/Php/PhpSettingsHandler.php(33): _HumbugBox113887eee2b6\KevinGH\Box\Console\Php\PhpSettingsHandler->bumpMemoryLimit()
2 phar://box.phar/src/functions.php(124): _HumbugBox113887eee2b6\KevinGH\Box\Console\Php\PhpSettingsHandler->check()
3 phar://box.phar/src/Console/Command/Compile.php(105): _HumbugBox113887eee2b6\KevinGH\Box\check_php_settings(Object(_HumbugBox113887eee2b6\Kevin in phar://box.phar/src/functions.php on line 81

### Additional contract requirements

- `format_size($size, int $decimals = 2)` formats the numeric value using exactly `$decimals` decimal places (default `2`). For example `format_size(1024, 0)` returns `"1KB"` and `format_size(1024, 3)` returns `"1.000KB"`.
- When `$size` is neither an `int` nor a `float`, `format_size` throws an `InvalidArgumentException`.
