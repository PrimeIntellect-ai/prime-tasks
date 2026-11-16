Argument 1 passed to DH\\Auditor\\Model\\Entry::sort() must be of the type array, null given
<!--
- Please do not report an issue for a version of `auditor` that is no longer supported. Currently supported versions are listed here: https://github.com/DamienHarper/auditor#version-information
- Please fill in this template according to your issue.
- Please keep the table shown below at the top of your issue.
- You can retrieve `auditor` version by running `composer info | grep "auditor"`.
- You can retrieve PHP version by running `php -v`.
- Please post code as text (using proper markup). Do not post screenshots of code.
- Please remove this comment before submitting your issue.
-->



| Q                    | A
| ---------------------| -----------------------
| `auditor` version    | 4.0.3
| PHP version          | 7.3
| Database             | MariaDB

#### Summary

> Argument 1 passed to DH\\Auditor\\Model\\Entry::sort() must be of the type array, null given, called in /var/www/app/vendor/damienharper/auditor/src/Model/Entry.php on line 160

When viewing audit log for an entity that have done a insert and does not have any diff.

#### How to reproduce

Use the viewer and press "view audit" on a entity with entries that do not have a diff.

#### Expected behavior

Not an error
