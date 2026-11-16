Provide models with initial data
Sometimes a model needs information at initialization time, that you want to provide in a flexible way, something like:

```py
class MyModel(app.Model):

    def init(self, the_info):
         ...

...

m = MyModel(the_info=...)
```

Currently, the `init()` is always argumentless. The required behavior can be achieved by making a property `info`, the value of which can be used inside the `init()`. However, a property suggests that the info can be modified/reset after the model is instantiated, which is not always the case.

In other words, there are situations where a `Model` needs information at initialization time, but for which a property does not make sense conceptually.

Some possible solutions:

A. Any keyword arguments used to instantiate a `Model` which do not correspond to properties are passed to the `init()` as kwargs. You'd thus need to write it like `def init(self, info=None)` to make it a keyword arg. In theory it could also map to positional args by inspecting the signature, but that feels a bit too magical, I think.

I am a bit worried about error reporting if a user makes a type in a property name. We would need to inspect the `init()` sig to see what kwargs it accepts, so we can be sure that a kwarg is intended for the `init()`. This should thus be disallowed: `def init(self, **kwargs)`.

B. Provide a new kind of property, similar to the current `readonly` that *must* be provided at initialization and is readonly afterwards. This adds less conceptual stuff for the user to learn, as it's just a kind of property.

C. Use positional arguments. [HIDDEN] The only downside is that for Models run as an app via `app.launch` or `app.serve` we'd need to provide a way to set these args, but we already do that for the kwargs, so I guess that could work ...


cc @korijn @Maxyme

### Additional contract requirements

- When a model is constructed with positional arguments, pass those arguments as positional arguments to that model’s custom `init()` method.
