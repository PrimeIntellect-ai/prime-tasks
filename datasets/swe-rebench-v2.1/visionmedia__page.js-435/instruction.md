Context changes even if page.exit() includes redirect
In the following example, which is taken from code that imitates `beforeunload` in a dirty form checker. The first time through the code works as expected, but the second time through `path` will not match the `path` path that is set via the `page.replace()` call.

``` js

page.exit( '*', function( context ) {
  var path = context.path;
  setTimeout( function() {
    page.replace( path , null, false, false);
  }, 0);
} );
```

[HIDDEN]

### Additional contract requirements

- After an exit handler replaces the path without dispatching, a later exit handler should receive a context whose path matches the replaced path.
