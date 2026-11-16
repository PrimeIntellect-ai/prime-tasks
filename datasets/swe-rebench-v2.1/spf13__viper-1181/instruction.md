`svType != tvType` during config merge when keys can have different types
In [Lefhook git hooks manager](https://github.com/evilmartians/lefthook) we had ability to skip some git hooks in [user's local config](https://github.com/evilmartians/lefthook/blob/master/docs/full_guide.md#local-config). That was done via `skip` boolean setting in the config where usually it wasn't specified in main config defaulting to `false`, but in local config user could set it to `true`. However, reverse situations also exists in the wild.

Recently we decided to allow users not only skip hooks always (`true`) or never (`false`) but also by more complex conditions (e.g. during `rebase` and `merge`). This means, that this setting now can have different types of values in different configs: either boolean, string, or list of strings.

However, when we tried to merge configs with these “multitype” setting, values were ignored. I'm not sure whether it is a bug in Viper (I couldn't find any reasoning for the current implementation), but at least surprising behavior. If there is a way to properly handle this situation without changing Viper, please let us know!

**Expected behavior (what you expected to happen)**:
When I merge two configs with keys of different types, values are being overriden by values from merging config.

**Actual behavior (what actually happened)**:
New values are ignored with following messages printed to stderr:
```
ERROR 2021/05/22 12:16:28 svType != tvType; key=skip, st=string, tt=bool, sv=rebase, tv=true
ERROR 2021/05/22 12:16:28 svType != tvType; key=skip, st=[]interface {}, tt=bool, sv=[rebase merge], tv=true
```

**Repl.it link**:
https://replit.com/@Envek/Viper-example#main.go

**Code reproducing the issue**:
```go
viper := viper.New()
viper.AddConfigPath(".")

viper.SetConfigName("lefthook")
_ = viper.ReadInConfig()

viper.SetConfigName("lefthook-local")
_ = viper.MergeInConfig()

fmt.Printf("\nAll configuration: %+v\n\n", viper.AllSettings())
```

Configuration files:
<details>
<summary>lefthook.yml</summary>

```yml
post-checkout:
  piped: true
  scripts:
    01-bundle-checkinstall:
      skip: true
    02-db-migrate:
      skip: true
    03-crystalball-update:
      skip: true
```
</details>

<details>
<summary>lefthook-local.yml</summary>

```yml
post-checkout:
  scripts:
    01-bundle-checkinstall:
      skip: false
    02-db-migrate:
      skip: rebase
    03-crystalball-update:
      skip:
        - rebase
        - merge
```
</details>

**Environment**:
- Viper version: 1.7.1
- Config source: file
- File format: YAML

**Anything else we should know?**:
Pull request in Lefthook where this behavior was discovered (more context can be found here): https://github.com/evilmartians/lefthook/pull/173
Similar issue in Viper: https://github.com/spf13/viper/issues/1134
Commit that introduces code of interest: [`991d18a`](https://github.com/spf13/viper/commit/991d18afb2404beca5bc475995bf76f38729cc8f#diff-786d4c5d3482047f0ac7e62876791b9f4ba727a70acd750cf0a1bdd19c51c3f1R992-R997)

And thank you for Viper!
