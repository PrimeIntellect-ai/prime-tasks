adding to HandleInertiaRequests->share array no longer works in version 1.2.0
I have this code block that use to work in version 1.0.0. It is no longer working in version 1.2.0. It use to return the auth.user along with permissions. Now it appears that permissions is just overwriting the entire array and that is all that is returned.

//HandleInertiaRequests.php
```
public function share(Request $request): array
{
      return array_merge(parent::share($request), [
            'auth.user.permissions' => fn () => $request->user()->getAllPermissions(),
      ]);
}
```
Partial reload behaviour change in 1.1.0 causes lazy attributes not to be reloaded correctly
### Version:

- `@inertiajs/react` version: 1.1.0

### Describe the problem:

I updated Inertia a few minutes ago and found the following issue.
**Before the Update to 1.1.0:**
When having a list of objects 'foos', with each object having a lazy attribute like 'bar', reloading the list object foos, will result in the bar object being loaded in correctly.
```php
return Inertia::render('TestView', [
    'foos' => [
        [
            'bar' => Inertia::lazy(function () {
                return 'Test';
            })
        ],
        ...
    ]
])
```

```tsx
reload({
    only: [
        'foos'
    ],
});
```

**Current behaviour (after 1.1.0):**
When I now try to do the same, bar is not being loaded into the foo object. I think the partial reload changed in this specific version are faulty for that behavior.
