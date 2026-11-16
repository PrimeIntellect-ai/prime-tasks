Can no longer delete permissions returned by "findByName"
### Description

Before when doing:
$permission = Permission::findByName($name, $guardName);

And then calling:
$permission->delete()

The permission would be correct deleted.

Now this no longer happens because the [HIDDEN].

This behavior has changed since version 6.10.0, worked fine in 6.9.0.

### Steps To Reproduce

1. $permission = Permission::findByName($name, $guardName);
2. $permission->delete()
3. Notice the permission is not deleted.



### Example Application

_No response_

### Version of spatie/laravel-permission package:

6.10.0

### Version of laravel/framework package:

11.30.0

### PHP version:

8.3

### Database engine and version:

singlestore

### OS: Windows/Mac/Linux version:

Ubuntu

### Additional contract requirements

- A permission returned by `findByName($name, $guardName)` must be deletable so that its persisted record is removed.
