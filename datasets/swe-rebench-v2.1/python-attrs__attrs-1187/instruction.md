Pass all args to `__attrs_pre_init__()`
I am subclassing a class that I have no control over, which is written in standard Python.  The base class A has a number of arguments that I want to set.  Infact there are 3 classes.  C (attrs class) is a sublcass of B (attrs class) which is a subclass of A (non-attrs class).

When I instantiate C, I want to pass arguments to B and A.

I implemented class based factory functions (vai `@classmethod`), which works well for a single level inheritance, but I'm not sure how to use the classmethod of B from the classmethod of A.  I figured I'm stuck with duplicating of the B initialisation within the C classmethod and the instantiating class C by passing all the necessary arguments.

All this involves defining a custom `__init__()` method (https://www.attrs.org/en/stable/init.html#custom-init), but it seems to me that could be avoided by using `__attrs_pre_init__()`, but unfortunately it seems no arguments are passed to that (i.e. no `*args` or `**kwargs`).

Is there a reason why arguments are not passed to `attrs_pre_init__()`, and only passed to `__init__()`?

I think it makes sense to pass all arguments to `__attrs_pre_init__()` so the user can have the flexibility to do what is required (or nothing at all).

```python

    def __attrs_pre_init__(self, *args, **kwargs):
        ...
        super().__init__(*args, **kwargs)
        ...
```

I can see why it is less relevant for `__attrs_post_init__()`, but I'm sure someone can think of a use-case where the arguments could be useful (e.g. for arguments that aren't stored as instanace attributes).
