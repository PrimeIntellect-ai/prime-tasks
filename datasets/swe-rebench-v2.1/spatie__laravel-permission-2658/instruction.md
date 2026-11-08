Cannot save the user model twice in the same request
**Describe the bug**
Hi,
Sorry if this has already been asked but I'm using Laravel fortify to register new users, once user is registered I automatically log him in but I have a listener that listens for Login and automatically edits the user IP and last login and saves the user again. When the user is saved again I get an error Duplicate entry '7-153-User' for key 'model_has_roles.PRIMARY'.
I fixed the issue by saving quietly but is this expected behavior ?
Now everytime I save a user in the same lifetime cycle it just crashes.
[HIDDEN] see #2420
Did not have this issue before because I migrated from v4 to v6.

**Versions**
- spatie/laravel-permission package version: 6.4.0
- laravel/framework package: 10.48.3

PHP version: 8.2.16

Database version: mysql 8.0.32


**To Reproduce**

- Create a new User
- Sync or Assign role to the user
- Save the User
- Save the User again

My listener:
```php
public function login(Login $event): void
    {
        try {
            /** @var User $user */
            $user = $event->user;
            activity('Auth')->by($user)
                ->withProperty('IP', request()->getClientIp())
                ->log('Login');

            $user->last_login = Carbon::now();
            $user->last_ip = request()->getClientIp();
            $user->saveQuietly();
        } catch (\Exception $exception) {
            report($exception);
        }
    }
```

**Expected behavior**
I would expect the save to not throw an error if I save the User twice.

**Environment (please complete the following information, because it helps us investigate better):**
 - OS: ubuntu
 - Version: 22.04
