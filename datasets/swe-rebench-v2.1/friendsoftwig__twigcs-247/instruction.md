Support config files with `.php` extension
In addition to the already supported `.twig_cs` and `.twig_cs.dist` files, I suggest to add the support for `.twig_cs.php` and `.twig_cs.dist.php`
Inspired from PHP-CS-Fixer, they already did that in https://github.com/FriendsOfPHP/PHP-CS-Fixer/pull/5607, they also have removed the support of old names in https://github.com/FriendsOfPHP/PHP-CS-Fixer/pull/5609

Benefits of this move are:
- IDE will automatically detect the file as being a PHP file
- the config file can be targeted in a generic way with `*.php` like other PHP files to be included in other CS tools like PHP-CS-Fixer, PHP_CodeSniffer, etc, no need to maintain it as a particular case

I can try to come with a PR if the idea is accepted

### Additional contract requirements

- When searching for a default config file in the current working directory, use this precedence order: `.twig_cs.php`, `.twig_cs`, `.twig_cs.dist.php`, then `.twig_cs.dist`.
