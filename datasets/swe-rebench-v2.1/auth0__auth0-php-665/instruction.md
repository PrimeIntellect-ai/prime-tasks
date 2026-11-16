Recent changes break existing auth0/login configuration
### SDK Version

8.3

### PHP Version

PHP 8.1

### What happened?

Recent changes to this library (#659) and to the Laravel library (auth0/login, https://github.com/auth0/laravel-auth0/commit/e132b28b9fb623339ba1f236f6430effa29f2c89) break backward compatibility.

`SdkConfiguration::setScope()` no longer handles a `null` empty value correctly. Although the recent change to auth0/login corrects this for anyone who installs and publishes the Laravel configuration after auth0/login:7.2.2, anyone with an **existing configuration** file (which would have code like this: `Configuration::stringToArrayOrNull(env('AUTH0_SCOPE')),`)  will default their scope to null.

This library should be able to handle both empty states, empty array and null.

[HIDDEN]

There may be additional test cases required here.


### How can we reproduce this issue?

- Install Laravel.
- Composer-require auth0/auth0-php:8.3.0.
- Composer-require auth0/login:7.1.0.
- `php artisan vendor:publish --tag=auth0-config`
- set up the rest of the app per the instructions.
- Loosen Composer requirements to `auth0/auth0-php:^8.3.0` and `auth0/login:^7.1.0`
- composer update
- confirm that `Validation of "scope" was unsuccessful` is reported.

### Additional context

_No response_

### Additional contract requirements

- `SdkConfiguration::setScope()` accepts `null` as well as an array of scope strings. When `null` or an empty array is supplied, the scope resolves to the default list `['openid', 'profile', 'email']`.
- `SdkConfiguration::getScope()` returns the resolved scope array, which is `['openid', 'profile', 'email']` when the configured scope is `null` or an empty array.
- A non-empty array of scope strings supplied as the scope is used as-is.
