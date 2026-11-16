Add a `plt_ignore_app(s)` option
### Current behavior

Some apps ([Saxy is an example](https://github.com/qcam/saxy/issues/39)) take a very large amount of time to pass the dialyzer for certain versions of OTP. If we can pinpoint which dependency takes so long, we should be able to ignore only that dependency.

Currently if I want to ignore a single dependency, I need to make a configuration that looks like this:

```elixir
   # mix.exs, project section
  ...
  dialyzer: [
    ignore_warnings: ".dialyzer_ignore.exs",
    plt_apps: [
      :erts,
      :kernel,
      :stdlib,
      ... # all other dependencies except the one that hangs
    ]
  ]
```

### Expected behavior

I'd like to be able to just say the app I'd like to ignore:

```elixir
   # mix.exs, project section
  ...
  dialyzer: [
    ignore_warnings: ".dialyzer_ignore.exs",
    plt_ignore_apps: [:saxy]
  ]
```

[HIDDEN] If you like the idea, I'd be happy to send in a PR

### Additional contract requirements

- When dependency apps are automatically included in the PLT app set, `plt_ignore_apps` omits the configured app or apps while leaving unignored dependency apps available.
