Feature Request: `UseAnonymousMigrations` lint
Would be awesome if tlint could prefer anonymous class migrations in Laravel:

https://laravel.com/docs/8.x/migrations#anonymous-migrations

### Additional contract requirements

The lint reports named classes that extend Laravel's `Migration` base class, but does not report named classes that are not migrations. It also does not report an anonymous migration class.
