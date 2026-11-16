Error using pagination in index method
<!-- PLEASE COMPLETE THIS TEMPLATE -->

- Laravel Version: 8.31.0
- PHP Version: 7.4.3
- Blueprint Version: 1.22.0
- Platform: Linux

### Issue: Error using pagination in index method.
Hello.
When I define a controller specifying the resource type as `resource: api` and in the `index` method it is specified as `query: all` and `resource: 'paginate:posts'`, as shown below:
```yaml
models:
  Post:
    title: string
    body: text
controllers:
  Post:
    resource: api
    index:
      query: all
      resource: 'paginate:posts'
seeders: Post
```

The above code generates the following files:
![imagen](https://user-images.githubusercontent.com/4079493/110160013-7036e680-7db9-11eb-9c99-f17b32f93e2d.png)

The problem comes in the index method of the controller:
```php
public function index(Request $request)
{
    $posts = Post::all();

    return new PostCollection($posts->paginate());
}
```
First it generates a `$posts` variable and assigns it the results of `Post::all()` and then tries to call the `paginate()` method on the `$post` variable. This leads to an error when I make a request to the api/post route:
![imagen](https://user-images.githubusercontent.com/4079493/110160983-ba6c9780-7dba-11eb-809e-4e54818ed1bb.png)
```json
{
    "exception": "BadMethodCallException",
    "file": "/home/cristian/Proyectos/blueprint-test/vendor/laravel/framework/src/Illuminate/Macroable/Traits/Macroable.php",
    "line": 103,
    "message": "Method Illuminate\\Database\\Eloquent\\Collection::paginate does not exist.",
    "trace": [
        {
            "class": "Illuminate\\Support\\Collection",
            "file": "/home/cristian/Proyectos/blueprint-test/app/Http/Controllers/PostController.php",
            "function": "__call",
            "line": 22,
            "type": "->"
        }
     ]
}
```

The correct code that should be generated is:
```php
public function index(Request $request)
{
    $posts = Post::paginate();

    return new PostCollection($posts);
}
```

### draft.yaml:
```yaml
models:
  Post:
    title: string
    body: text
controllers:
  Post:
    resource: api
    index:
      query: all
      resource: 'paginate:posts'
seeders: Post

```
