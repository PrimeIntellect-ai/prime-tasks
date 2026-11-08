@role is not accepting an array
He, I'm check on multiple gaurds but is not working. If I just pass through 'admin' it works.

```php
@role('superadmin', 'admin')
# you may edit this stuff
@else # this is error some times
# you may not edit this stuff
@endrole

```
In the readme [here](https://github.com/spatie/laravel-permission#using-blade-directives-with-multiple-guards) it says that it should work. But it does not.
Blade directive `@hasanyrole` does not work with array of role names
Using blade templates this works:
```blade
@hasanyrole('admin|manager')
        It works
@endhasanyrole
```

Unfortunately this piece of code raises an error:
```blade
@hasanyrole(['admin', 'manager'])
        This should work, too
@endhasanyrole
```

The error points to the line with `@hasanyrole` and says: `ParseError syntax error, unexpected ']', expecting ')'`

According to documentation at https://spatie.be/docs/laravel-permission/v5/basic-usage/blade-directives we should be able to pass `$collectionOfRoles`

PS. This works as well:
```blade
@if(auth()->user()->hasAnyRole(['admin', 'manager']))
        This works as well
@endif
```

**Versions**
- spatie/laravel-permission package version: 5.5.5
- laravel: 8.79.0
- PHP version: 7.4.19
- Database version: 10.6.4-MariaDB-log

**Expected behavior**
`@hasanyrole` should accept arrays
