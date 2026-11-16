UPGRADE.md file missing with broken link for php-cs-fixer self-update
## Bug report

From PHP CS Fixer updated (2.18.2 -> v3.0.2)

```
$ php-cs-fixer self-update
A new major version of PHP CS Fixer is available (v3.0.2)
Before upgrading please read https://github.com/FriendsOfPHP/PHP-CS-Fixer/blob/v3.0.2/UPGRADE.md
If you are ready to upgrade run this command with -f
Checking for new minor/patch version...

```
The file https://github.com/FriendsOfPHP/PHP-CS-Fixer/blob/v3.0.2/UPGRADE.md is missing

### Additional contract requirements

- When self-update reports a new major version, the upgrade-guide URL must be `https://github.com/FriendsOfPHP/PHP-CS-Fixer/blob/<major-release-version>/UPGRADE-v<next-major-number>.md`, where `<major-release-version>` is the new release version and `<next-major-number>` is its major version number.
