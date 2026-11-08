[Shock] - Pretty URLs aren't working for pages within a directory
A pretty URL is a URL that avoids the use of a specific file, e.g., `mydomain.com/posts/hello-world/` instead of `mydomain.com/posts/hello-world.html` or `mydomain.com/posts/hello-world/index.html`.

Some aspect of the pretty URL system is failing for pages that explicitly declare an index file.

Given the following structure:

```
source/
  posts/
    hello-world/
      index.md
```

The final URL is `mydomain.com/posts/hello-world/index.html` when instead it should be `mydomain.com/posts/hello-world/`.
