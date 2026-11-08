Inconsistent handling of option values from environment variables
There are 2 ways of configuring Click to load a value of a specific option from an environment variable: "automatic" via `auto_envvar_prefix` and "explicit" via passing `envvar` keyword argument to the option definition.

When a name of an environment variable is set explicitly, Click treats empty string values (i.e. `export MY_OPTION=`) as not set and keeps a default value (`None` if not configured otherwise). But when a name is inferred from `auto_envvar_prefix` configuration, Click treats empty string values as valid values, does not set a default and passes the option to `ParamType.convert()` if `type` keyword argument is specified for that option.

This is inconsistent.

```python
import click

@click.command()
@click.option('--auto')
@click.option('--ex', envvar="EXEV")
def cli(auto, ex):
    click.echo(f"{auto=} {type(auto)=}")
    click.echo(f"{ex=} {type(ex)=}")

if __name__ == '__main__':
    cli(auto_envvar_prefix='MY')
```

Actual output:

```shell
$ MY_AUTO= EXEV= ./cli.py
auto='' type(auto)=<class 'str'>
ex=None type(ex)=<class 'NoneType'>
```

Expected output:

```shell
$ MY_AUTO= EXEV= ./cli.py
auto=None type(auto)=<class 'NoneType'>
ex=None type(ex)=<class 'NoneType'>
```

Environment:

- Python version: `3.9.7`
- Click version: `8.0.3`

It's being a nuisance for quite a while at my company, we have `.env.example` file with variables containing multiple `export FOO=` lines for each project. When my colleagues work on the project, they just copy `.env.example` to `.env`, fill out required values (not all of the values) and then do a test run.

Then for variables like export `OPTIONAL_VALUE=` that are left as is, click loads them as empty strings and calls type validators `TypeInstance.convert()` with that value, which usually fails as an empty string is not a valid value for the majority of options.

[HIDDEN]

### Additional contract requirements

When an automatically inferred environment variable is empty, treat it as absent and use the option's normal default. If no default is configured, the option value is `None`.
