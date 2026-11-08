scoper-autoload.php doesn't support PHP 5.6
## Bug report

| Question    | Answer
| ------------| ---------------
| PHP-Scoper version | 0.18.3
| PHP version | 5.6
| Platform with version | all
| Github Repo | [- <!-- (if public) -->](https://github.com/skaut/skaut-google-drive-gallery/)

Hi,
I am using PHP-scoper for packaging a WordPress plugin, so I don't really get much control over which PHP versions it will be running with. Recently I got reports of ` syntax error, unexpected ‘:’, expecting ‘{‘` in the `scoper-autoload.php` file and was surprised to find that it contains return type annotations, possibly as an artifact from the build process. I tried to look for info about supported runtime php versions in the project, but couldn't find any

I assume composer minimum version is the version of PHP php-scoper runs on, but the output would respect the source code it processes...
