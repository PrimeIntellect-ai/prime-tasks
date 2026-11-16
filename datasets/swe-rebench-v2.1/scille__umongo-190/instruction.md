ValueError: microsecond must be in 0..999999
Hello, all

I've got a new error after the v2.0.0 milestone, likely relating to #172. Here's the error text:

```python
  File "/Users/space/Documents/Programming/dt-blog-platform/api-server/db/objs.py", line 268, in commit
    self.updatedon = datetime.datetime.utcnow()
  File "/var/root/.local/share/virtualenvs/api-server-DI-zCP9m/lib/python3.6/site-packages/umongo/document.py", line 295, in __setattr__
    self._data.set(name, value, to_raise=AttributeError)
  File "/var/root/.local/share/virtualenvs/api-server-DI-zCP9m/lib/python3.6/site-packages/umongo/data_proxy.py", line 152, in set
    value = field._deserialize(value, name, None)
  File "/var/root/.local/share/virtualenvs/api-server-DI-zCP9m/lib/python3.6/site-packages/umongo/fields.py", line 245, in _deserialize
    return ret.replace(microsecond=round(ret.microsecond, -3))
ValueError: microsecond must be in 0..999999
```

My guess is something funky is going on either with my system, or maybe the round isn't working properly? Not too sure, but this should be a simple one.

The way I did this is set a `StrictDateTimeField` equal to `datetime.datetime.utcnow()` in an overriden `commit` method. Ex:

```python
@instance.register
class Foo(Document):
    name = fields.StringField()
    updatedon = fields.StrictDateTimeField()

    def commit(self, *args, **kwargs):
        self.updatedon = datetime.datetime.utcnow()
        return super(Foo, self).commit(*args, **kwargs)
```

This error happens when calling the commit method on the object.

Thanks in advance!
