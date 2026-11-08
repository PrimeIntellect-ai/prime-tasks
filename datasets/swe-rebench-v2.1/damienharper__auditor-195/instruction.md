DoctrineSubscriber throw deprecation when Driver is wrapped with another class
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
| `auditor` version    | 2.4.7
| PHP version          | 8.1
| Database             | MySQL

#### Summary

I have both Auditor and Sentry packages.
Sentry also has a middleware that wraps connection with a special class.
Depending on priority of this middlewares `DoctrineSubscriber` may trigger a deprecation because $driver is not a `DHDriver`, but actually it's wrapped.


#### Current behavior

trigger deprecation when it's actually should not

#### How to reproduce

Install both damienharper/auditor-bundle and sentry/sentry-symfony

#### Expected behavior

correct detection of `DHDriver`
