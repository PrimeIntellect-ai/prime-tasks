Percent sign in URL results in a URI malformed error when using route().current()
### Ziggy version

2.3.0

### Laravel version

11.28.0

### Description

My website has profile section where you can view users usernames, the structure is site.com/user/{username}

We have a requirement to allow users to use the % sign in their username. I'm making sure to urlencode the username to prevent issues on the server side.

So for example a URL might be site.com/user/john%25

The issue comes when I call route().current('user.profile'), I get the following error in my browser: `URIError: URI malformed`

![image](https://github.com/user-attachments/assets/758d7b87-df13-4b48-a649-4e00b1f80c53)



### Ziggy call and context

```js
route().current('user.profile')
```


### Ziggy configuration

```js
Can provide if needed.
```


### Route definition

```php
Route::get('/user/{username}', [PageController::class, 'userProfile'])->name('user.profile');
```
