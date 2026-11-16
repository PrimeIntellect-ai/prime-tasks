Artisan permission:show command incorrect roles with underscores.
**Describe the bug**
When executing `./artisan permission:show`, roles with underscores in them only show up until the first underscore.

**Versions**
You can use `composer show` to get the version numbers of:
- spatie/laravel-permission package version: 5.10.0
- illuminate/framework package: 10.3.1 (Laravel framework version, I can't find illuminate/framework in the output of `composer show`)

PHP version: 8.2.4

Database version: mariadb  Ver 15.1 Distrib 10.11.2-MariaDB, for Linux (x86_64) using readline 5.1

**To Reproduce**
Steps to reproduce the behavior:
1. Create a role with an underscore in it
2. Run `./artisan permission:show

Here is my example code and/or tests showing the problem in my app:
```
+-------------------------------+-------+----------+----------+-------------+------+
|                               | admin | employee | employee | employee-hr | user |
+-------------------------------+-------+----------+----------+-------------+------+
| add_employee                  |  ·    |  ·       |  ·       |  ·          |  ·   |
| delete_own_user_account       |  ·    |  ·       |  ·       |  ·          |  ✔   |
| edit_any_user_info            |  ·    |  ·       |  ·       |  ✔          |  ·   |
| edit_own_user_info            |  ·    |  ·       |  ·       |  ·          |  ✔   |
| view_all_permissions          |  ·    |  ·       |  ✔       |  ·          |  ·   |
| view_all_roles                |  ·    |  ·       |  ·       |  ✔          |  ·   |
| view_all_users                |  ·    |  ·       |  ·       |  ✔          |  ·   |
| view_basic_server_info        |  ·    |  ·       |  ✔       |  ·          |  ·   |
| view_detailed_server_info     |  ·    |  ·       |  ·       |  ·          |  ·   |
| view_general_employee_content |  ·    |  ✔       |  ·       |  ·          |  ·   |
| view_own_user_info            |  ·    |  ·       |  ·       |  ·          |  ·   |
+-------------------------------+-------+----------+----------+-------------+------+
```

**Expected behavior**
The second `employee` should say `employee_it`.

**Environment (please complete the following information, because it helps us investigate better):**
 - OS: Arch Linux
 - Version: Latest updates
