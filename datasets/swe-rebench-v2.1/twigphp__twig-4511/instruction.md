Issue with the `guard` tag
I updated a bundle to start using the new `guard` tag: https://github.com/EasyCorp/EasyAdminBundle/pull/6656

However, instead of the expected `guard` behavior, in tests you can now see a lot of messages like:

```
"Did you forget to run "composer require symfony/web-link"?
Unknown function "preload" in "@EasyAdmin/includes/_css_assets.html.twig"."
at UndefinedCallableHandler.php line 105
```

As @stof explained on Symfony Slack, this only happens when using Twig inside a Symfony application, where this class exists --> https://github.com/symfony/symfony/blob/7.3/src/Symfony/Bridge/Twig/UndefinedCallableHandler.php

[HIDDEN]

Thanks!

### Additional contract requirements

- When a `guard` tag checks whether a function exists, an undefined-function callback must not make the check fail with an error. If the function is unavailable, the guard must handle it as unavailable.
