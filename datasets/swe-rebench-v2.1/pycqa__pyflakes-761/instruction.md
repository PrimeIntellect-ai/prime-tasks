should produce error for attribute hidden by a method
# How to reproduce

```
$ flake8 --version
6.0.0 (mccabe: 0.7.0, pycodestyle: 2.10.0, pyflakes: 3.0.1) CPython 3.11.1 on Linux
$ flake8 ok.py
ok.py:5:5: F811 redefinition of unused 'bar' from line 2
$ flake8 fail.py
```

## `ok.py`

```python
class Foo:
    def bar(self):
        return 0

    def bar(self):
        return 1
```

## `fail.py`

```python
class Foo:
    bar = 0

    def bar(self):
        return 1
```

# Reasons

I do understand that redefinition of variables is a useful pattern, for example [`structlog` Bound Loggers](https://www.structlog.org/en/stable/bound-loggers.html) uses it extensively.

```python
log = structlog.get_logger()
log = log.bind(user=user)
log = log.bind(time=now())
log.info('hello world')
```

## Problems

I spent some time debugging a problem in our code base related to [Factory Boy Lazy Attributes](https://factoryboy.readthedocs.io/en/stable/#lazy-attributes).

```python
class UserFactory(Factory):
    class Meta:
        model = User

    name = 'joe'
    email = LazyAttribute(lambda user: f'{user.name}@example.com')

    # A 1000 lines later

    @post_generation
    def email(self):
        return 'fake@stub.io'
```

## Proposal

Deny attribute redefinition inside class body.

Thoughts?
