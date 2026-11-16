Error searchQuery when using laravel/spatie-permission
### Laravel Rest Api Version

1.1.1

### Laravel Version

10.24.0

### PHP Version

8.1

### Database Driver & Version

_No response_

### Description

Error: Call to a member function resource() on null in file /var/www/vendor/lomkit/laravel-rest-api/src/Http/Response.php on line 92

This error occurs when using laravel/spatie-permission. By including roles in the User model via the variable $with because the relationship with roles is defined directly with the package, so I didn't define it in the UserResource.

### Steps To Reproduce

- Add laravel/spatie-permission
- Set-up roles/permissions migrations
- Add $with in model User `protected $with = ['roles'];`
- Try to use search method `users/search`

### Additional contract requirements

- When a search is made without requested includes, an automatically eager-loaded `belongsToRelation` that is registered as a REST relation must still appear in each result under the exact key `belongs_to_relation`; its value must contain the related resource's exposed fields, or be `null` when no related model exists.
