bug: Provider doesn't override factory with lower scope
```python
from dishka import Provider, make_container, Scope, provide


class RealProvider(Provider):
    @provide(scope=Scope.REQUEST)
    def get_int(self) -> int:
        return 1


class FakeProvider(Provider):
    @provide(scope=Scope.APP)
    def get_int(self) -> int:
        return 42


class Interactor:
    def __init__(self, dep: int) -> None:
        self.dep = dep

    def __call__(self) -> int:
        return self.dep


class ServiceProvider(Provider):
    get_interactor = provide(Interactor, scope=Scope.REQUEST)


container = make_container(RealProvider(), ServiceProvider(), FakeProvider())
with container() as request_container:
    service = request_container.get(Interactor)
    assert service() == 42  # AssertionError 1 != 42
```

Expected behavior: `FakeProvider` has a bigger prior than `RealProvider`, so `int` dependency should be `42`

Btw, the following code works fine

```python
class RealProvider(Provider):
    @provide(scope=Scope.APP)
    def get_int(self) -> int:
        return 1

class FakeProvider(Provider):
    @provide(scope=Scope.REQUEST)
    def get_int(self) -> int:
        return 42
```
