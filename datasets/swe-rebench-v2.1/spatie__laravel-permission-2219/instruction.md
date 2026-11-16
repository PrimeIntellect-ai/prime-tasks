Undefined index: guard_name
**Describe the bug**
This afternoon I upgraded the version of this package we're using to [5.5.10](https://github.com/spatie/laravel-permission/releases/tag/5.5.10) and then started seeing an error to do with guard_name being undefined:

```
ErrorException
Undefined index: guard_name

Illuminate\Foundation\Bootstrap\HandleExceptions::handleError
vendor/spatie/laravel-permission/src/Models/Role.php:73
```

That line consists of
```
[HIDDEN]
```

I've downgraded back to 5.5.9 for now which no longer causes the error. It would be good if someone could take a look into this though!

**Versions**
- spatie/laravel-permission package version: **5.5.10**
- illuminate/framework package version: **8.83.25**
- PHP version: **7.4**
- Database version: **MySQL 5.7**


**To Reproduce**
Here is my example code and/or tests showing the problem in my app:
```
Role::with('users')->get();
```
causes the error, however
```
Role::with('permissions')->get();
````
works fine

**Expected behavior**
I'd expect roles to be returned with users that have the role
