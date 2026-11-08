Can't use `postgresql+psycopg2://...` with `PostgresDsn `
### Checks

* [x] I added a descriptive title to this issue
* [x] I have searched (google, github) for similar issues and couldn't find anything
* [x] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this is a bug

<!-- Sorry to sound so draconian, but every second saved replying to issues is time spend improving pydantic :-) -->

# Bug

I'm expecting to be able to use a database connection url such as `postgresql+psycopg2://user:pass@localhost:5432/app` (a format [SQLAlchemy is supporting](https://docs.sqlalchemy.org/en/14/dialects/postgresql.html#dialect-postgresql-psycopg2-connect)).

However, it doesn't seem to accept the `+psycopg2` part.

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
             pydantic version: 1.8.1
            pydantic compiled: False
                 install path: /Users/krisb/Code/fork/pydantic/pydantic
               python version: 3.7.10 (default, Apr 12 2021, 03:46:49)  [Clang 12.0.0 (clang-1200.0.32.29)]
                     platform: Darwin-20.3.0-x86_64-i386-64bit
     optional deps. installed: ['devtools', 'dotenv', 'email-validator', 'typing-extensions']
```
<!-- or if you're using pydantic prior to v1.3, manually include: OS, python version and pydantic version -->

<!-- Please read the [docs](https://pydantic-docs.helpmanual.io/) and search through issues to
confirm your bug hasn't already been reported. -->

<!-- Where possible please include a self-contained code snippet describing your bug: -->

Changed test https://github.com/samuelcolvin/pydantic/blob/7af90a8d6c1c406799ad95b81e353b386cde5745/tests/test_networks.py#L318-L318 to include
```py
assert Model(a='postgresql+psycopg2://user:pass@localhost:5432/app').a == 'postgresql+psycopg2://user:pass@localhost:5432/app'
```
pytest error output:
```
...
>           raise validation_error
E           pydantic.error_wrappers.ValidationError: 1 validation error for Model
E           a
E             URL scheme not permitted (type=value_error.url.scheme; allowed_schemes={'postgres', 'postgresql'})

pydantic/main.py:400: ValidationError
```

This is similar to https://github.com/samuelcolvin/pydantic/issues/1142, and a workaround for now is to use `AnyUrl` where this type of URL is supported.

### Additional contract requirements

- `PostgresDsn` must also accept `postgresql+asyncpg://user:pass@localhost:5432/app` and preserve its string value exactly.
