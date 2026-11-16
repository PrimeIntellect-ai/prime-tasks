scoper should copy file permissions
## Bug report

| Question    | Answer
| ------------| ---------------
| PHP-Scoper version | 0.14.0
| PHP version | 7.4.16
| Platform with version | Alpine Linux 3.13.2

Scoper does not preserve file permissions when copying. I observed this for script files which are used in composer config:

```console
$ ls -lh bin
-rwxrwxr-x    1 root     root        2.8K Mar 15 20:31 post-install-update.sh
-rwxrwxr-x    1 root     root        1.2K Mar 15 20:31 scoper-fix-autoloader.php
$ php-scoper add-prefix
    ____  __  ______     _____
   / __ \/ / / / __ \   / ___/_________  ____  ___  _____
  / /_/ / /_/ / /_/ /   \__ \/ ___/ __ \/ __ \/ _ \/ ___/
 / ____/ __  / ____/   ___/ / /__/ /_/ / /_/ /  __/ /
/_/   /_/ /_/_/       /____/\___/\____/ .___/\___/_/
                                     /_/

PHP Scoper version 0.14.0 2020-12-21 14:36:07 UTC

 3215/3215 [▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓] 100%


 [OK] Successfully prefixed 3215 files.


 // Memory usage: 31.77MB (peak: 49.64MB), time: 14.78s


$ ls -lh build/bin/
total 8K
-rw-r--r--    1 root     root        2.8K Mar 15 20:49 post-install-update.sh
-rw-r--r--    1 root     root        1.2K Mar 15 20:49 scoper-fix-autoloader.php
```
