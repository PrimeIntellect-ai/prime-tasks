@deprecated breaking __init__ inheritance when used with mixins/multiple inheritance
When a class without `__init__` (mixin) is used in multiple inheritance and marked as deprecated, inheritance of `__init__` doesn't work.

Example:

```py
from typing_extensions import deprecated


class Service:
    def __init__(self, foo: str, bar: str) -> None:
        print("Service.__init__")
        self.foo = foo
        self.bar = bar

    def echo(self) -> None:
        print("Service.echo", self.foo, self.bar)


class Base:
    def message(self) -> None:
        print("Base.message")


class Child(Base):
    def message(self) -> None:
        print("Child.message")
        super().message()


@deprecated("Use Child instead")	# removing this will work normally
class FooBarPrinter(Child):
    def message(self) -> None:
        print("FooBarPrinter.message")
        super().message()


class Spam(Service, FooBarPrinter):
    def do_work(self):
        self.echo()
        self.message()


if __name__ == "__main__":
    Spam("foo", "bar").do_work()
```
