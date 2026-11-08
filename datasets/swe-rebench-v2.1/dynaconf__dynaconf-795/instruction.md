Env vars are case sensitive (overriding only uppercase params if written in uppercase)  when merge_enabled=True
Let's say i have very simple yaml config with envs:
```yaml
default:
  my_section:
    my_param: "default settings content"
development:
  my_section:
    my_param: "development settings content"
```
And i want to override `my_param` with env variable at some point. What's proper env var name for such case? `DYNACONF_MY_SECTION__MY_PARAM` works if `merge_enabled=False`.
However, if `merge_enabled=True`, `DYNACONF_MY_SECTION__MY_PARAM` will set my_section.MY_PARAM, not my_section.my_param.
Easy reproducer:
```python
import os
import dynaconf


os.environ["DYNACONF_MY_SECTION__MY_PARAM"] = "env var content"

settings = dynaconf.LazySettings(
	environments=True,
	env="development",
	settings_files=["settings.yaml"],
	merge_enabled=True,
)

print(settings.my_section.my_param)
print(settings.my_section.MY_PARAM)

```
Running the code returns the following output:
```
development settings content
env var content
```
setting `merge_enabled=False` and re-running the code returns expected output:
```
env var content
env var content
```
Documentation is kinda confusing about this behavior, so i'm not 100% sure it's a bug:
On the one hand, https://www.dynaconf.com/envvars/ examples are showing uppercase env vars are correctly recognized:
```
export DYNACONF_PERSON__IS_ADMIN=true
assert settings.person.is_admin is True
```
And it works like that with `merge_enabled=False`
On the other -  there's the following line:
```
Also variable access is case insensitive for the first level key
```
And there's https://www.dynaconf.com/configuration/#lowercase_read , so it looks like only the first level keys are designed to be case insensitive.

I'm using dynaconf 3.1.7, OS is macOS 12.2.1 if that matters.

### Additional contract requirements

The issue title above describes the buggy behavior that was reported. The
required behavior is the opposite: environment-variable keys are matched
against the existing configuration keys case-insensitively, and the existing
key's casing is preserved. For example, given a YAML file

```yaml
level1:
  key: key_value
  KEY2:
  key3:
  keY4:
```

and the environment variables `DYNACONF_LEVEL1__KEY`, `DYNACONF_LEVEL1__KEY2`,
`DYNACONF_LEVEL1__key3` and `DYNACONF_LEVEL1__KEY4`, each environment variable
overrides the corresponding existing key, and the value is stored under the
existing spelling so that `level1.key`, `level1.KEY2`, `level1.key3` and
`level1.keY4` all return the environment value. This holds for both
`merge_enabled=True` and `merge_enabled=False`.
