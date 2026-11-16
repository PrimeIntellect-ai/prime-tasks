Component logging hierarchy setup is broken
**Describe the bug**
Setting up the hierarchy of loggers is currently broken (and at least since 0.12).

[HIDDEN]

**To Reproduce**
```
from ctapipe.core import Tool, Component


class Foo(Component):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        print(self.log)


class Bar(Component):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        print(self.log)
        self.foo = Foo(parent=self)

class Baz(Tool):
    name = 'baz'

    def setup(self):
        self.bar = Bar(parent=self)

    def start(self):
        print(self.log)


if __name__ == '__main__':
    Baz().run()
```

prints

```
<Logger __main__.Bar (WARNING)>
<Logger __main__.Foo (WARNING)>
<Logger ctapipe.baz (WARNING)>
```


**Expected behavior**
Hierarchy is setup correctly.

### Additional contract requirements

- When a `Component` is constructed with a parent, its logger must be named beneath the parent’s logger using the component class name. This hierarchy must compose through nested Components.
