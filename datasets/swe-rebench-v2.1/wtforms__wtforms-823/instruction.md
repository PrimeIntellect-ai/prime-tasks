SelectMultipleField should support choices specified as coercible values.
### Actual Behavior

```python
>>> class DummyPostData(dict):
...     def getlist(self, key):
...             v = self[key]
...             if not isinstance(v, (list, tuple)):
...                     v = [v]
...             return v
...
>>> import wtforms
>>> class F(wtforms.Form):
...     foo=wtforms.SelectMultipleField(choices=[('1', 'One'), ('2', 'Two')], coerce=int)
...
>>> post_data = DummyPostData(foo=["1", "2"])
>>> form = F(post_data)
>>> form.validate()
False
>>> form.errors
{'foo': ["'1', '2' are not valid choices for this field."]}
```

### Expected Behavior

The form should be valid when the post data is a valid option after coercing both post data and choices:

```python
>>> class DummyPostData(dict):
...     def getlist(self, key):
...             v = self[key]
...             if not isinstance(v, (list, tuple)):
...                     v = [v]
...             return v
...
>>> import wtforms
>>> class F(wtforms.Form):
...     foo=wtforms.SelectMultipleField(choices=[('1', 'One'), ('2', 'Two')], coerce=int)
...
>>> post_data = DummyPostData(foo=["1", "2"])
>>> form = F(post_data)
>>> form.validate()
True
```


### Environment

* Python version: 3.9
* wtforms version: 3.1.1
