Subclassed `MethodView` resources cannot be added as URL rules
If you attempt to subclass an instance of `MethodView` with existing URL methods, perhaps with some extra logic, that subclassed view throws an error when `APIFlask.add_url_rule` gets called.

```
In [1]: from apiflask import APIFlask

In [2]: from flask.views import MethodView

In [3]: class Foo(MethodView):
   ...:     text = "This comes from `Foo`"
   ...:
   ...:     def get(self):
   ...:         return self.text
   ...:

In [4]: class FooSubclass(Foo):
   ...:     text = "This comes from `FooSubclass`"
   ...:

In [5]: app = APIFlask('mock_app')

In [6]: app.add_url_rule('/foo', view_func=FooSubclass.as_view('foo'))
---------------------------------------------------------------------------
KeyError                                  Traceback (most recent call last)
<ipython-input-6-82066accc4da> in <module>
----> 1 app.add_url_rule('/foo', view_func=FooSubclass.as_view('foo'))

.../lib/python3.8/site-packages/apiflask/route.py in add_url_rule(self, rule, endpoint, view_func, provide_automatic_options, **options)
     92                 # record spec for MethodView class
     93                 if hasattr(self, 'enable_openapi') and self.enable_openapi:
---> 94                     view_func = record_spec_for_view_class(view_func, view_class)  # type: ignore
     95
     96         super(cls, self).add_url_rule(

.../lib/python3.8/site-packages/apiflask/route.py in record_spec_for_view_class(view_func, view_class)
     40         for method_name in view_class.methods:  # type: ignore
     41             # method_name: ['GET', 'POST', ...]
---> 42             [HIDDEN]
     43             # collect spec info from class attribute "decorators"
     44             if hasattr(view_func, '_spec') and view_func._spec != {}:

KeyError: 'get'

In [7]: app.add_url_rule('/foo', view_func=Foo.as_view('foo'))
```

I would expect the registration of `FooSubclass` on line 8 to not fail.
[HIDDEN]

I am happy to open a PR fixing this bug. Should regression tests be added in [`tests/test_app.py`](https://github.com/apiflask/apiflask/blob/main/tests/test_app.py)?

Environment:

- Python version: 3.8.18
- Flask version: 2.2.2
- APIFlask version: 2.2.1
