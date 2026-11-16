Starting `Cachex` via `Supervisor.start_link`
Hello there,

I *really* hope I'm not wasting anyone's time here, but I simply went and read the "welcome page/guide" of this (awesome!) package and I've got myself a papercut.

[I read](https://hexdocs.pm/cachex/overview.html#setting-up) from the docs, in regards of starting `Cachex` in a supervision tree:
```ex
children = [
  {Cachex, [:my_cache]},     # with default options
  {Cachex, [:my_cache, []]}  # with custom options
]
```

So I try this in my phoenix application; I copy-paste the first line in my list of `children`:
```ex
children = [
  ...,
  {Cachex, [:my_cache]},
]
```

But, `Supervisor.start_link` gives this error:
```
** (Mix) Could not start application my_app: MyApp.Application.start(:normal, []) returned an error: shutdown: failed to start child: Cachex
    ** (EXIT) :invalid_name
```

Whereas, if I write my cache name like below, no error is raised on startup:
```ex
{Cachex, name: :my_cache},
```

Which makes sense, AFAIK supervisor wants a keyword list as a second argument of the tuple.

But... am I doing this right? Am I missing something?
