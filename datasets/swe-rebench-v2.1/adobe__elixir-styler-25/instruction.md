Produces compiler errors for Ecto queries using "in" macro
## Elixir / OTP Version
```
❯ cat .tool-versions
elixir 1.14.1-otp-25
erlang 25.1.1
```

## Current Behaviour

For several of my work projects, we do `require Ecto.Query` (instead of `import Ecto.Query, only: ...`) and then call `Ecto.Query.from(...)`. Inside of [the `from` macro](https://github.com/elixir-ecto/ecto/blob/v3.10.1/lib/ecto/query.ex#L939), an unqualified `in` is valid. However, `elixir-styler` makes the following change:

<img width="1137" alt="Screenshot 2023-05-04 at 8 22 32 AM" src="https://user-images.githubusercontent.com/3588798/236254197-8f819b66-b088-44fb-a180-d8ed3b636e2b.png">

<img width="1165" alt="Screenshot 2023-05-04 at 8 10 36 AM" src="https://user-images.githubusercontent.com/3588798/236251322-8bae6844-4450-4e90-959d-d63b304d2bda.png">

Which causes a compilation error:
```
syntax error before: in. "in" is a reserved word in Elixir and therefore its usage is limited. For instance, it can't be used as a variable or be defined nor invoked as a regular function
```

[HIDDEN]

## Expected Behaviour

I'm not sure how to avoid this, unless `elixir-styler` is able to detect which functions are macros and skip them or automatically fully qualify them?

### Additional contract requirements

- Styling an `Ecto.Query.from(...)` query that uses an unqualified `in` must not produce output that fails with the reported reserved-word syntax error.
