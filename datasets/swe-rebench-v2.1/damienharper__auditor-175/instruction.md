Invalid audit table name with schema
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
| PHP version          | 8.2
| Database             | PostgreSQL

#### Summary

Invalid computed audit table name if I use Doctrine schema

#### Current behavior

prefixschema.%table%suffix

#### How to reproduce

create entity with schema

#### Expected behavior

schema.prefix%table%suffix
