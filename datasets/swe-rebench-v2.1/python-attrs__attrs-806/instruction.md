`attr.evolve` no longer supports setting an attr object as attribute
Hi,

I don't know if this is an intentional side-effect of #759, but `attr.evolve` no longer works in the non-recursive recursive case if the argument is an attr class.

Here is a snippet to reproduce it:

```py
import attr

@attr.s
class Cls1:
    param1 = attr.ib()


@attr.s
class Cls2:
    param2 = attr.ib()


obj2a = Cls2(param2="a")
obj2b = Cls2(param2="b")

obj1a = Cls1(param1=obj2a)
obj1b = attr.evolve(obj1a, param1=obj2b)

print(obj1b)
```

Before fe6eb3120013833d1927374eb5e826b72815a775, it printed this: `Cls1(param1=Cls2(param2='b'))`

But after this commit, it raises this error:

```
Traceback (most recent call last):
  File "test.py", line 17, in <module>
    obj1b = attr.evolve(obj1a, param1=obj2b)
  File "/home/dev/.local/lib/python3.7/site-packages/attrs-21.2.0.dev0-py3.7.egg/attr/_funcs.py", line 347, in evolve
    changes[init_name] = evolve(value, **changes[init_name])
TypeError: evolve() argument after ** must be a mapping, not Cls2
```

Thanks!
