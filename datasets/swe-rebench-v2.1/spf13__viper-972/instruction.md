Allow multiple env. var. keys in BindEnv
It sometimes can happen that a project updates its conventions for environment variables, deprecating others while still wanting to offer support for them. For this reason it would be nice if `BindEnv` would allow this. The good news is that `BindEnv`'s function signature takes a variadic input so adding even more arguments to it would not be a breaking change.

An example of how it would work:

```go
viper.BindEnv("my.key", "APP_MY_KEY", "MY_KEY")
```

Then, when running `viper.Get("my.key")`, the first environment variable from the list would win. Basically the first entry is the latest valid form and the subsequent ones are the deprecated ones we want to keep support for.

Would it be ok to open a PR for this? It's a fairly small change with full backwards compatibility.
