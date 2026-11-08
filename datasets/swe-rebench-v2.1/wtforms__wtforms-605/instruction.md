Shortcut for SelectMultipleField choices
#526 brought a shortcut for `SelectField` choices, but this does not work with `SelectMultipleField`.

```python
>>> import wtforms
>>> class F(wtforms.Form):
...     single = wtforms.SelectField(choices=["foo", "bar", "baz"])
...     multiple = wtforms.SelectMultipleField(choices=["foo", "bar", "baz"])
>>> F().single()
Markup('<select id="single" name="single"><option value="foo">foo</option><option value="bar">bar</option><option value="baz">baz</option></select>')

>>> F().multiple()
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/azmeuk/dev/wtforms/.tox/py38/lib/python3.8/site-packages/wtforms/fields/core.py", line 177, in __call__
    return self.meta.render_field(self, kwargs)
  File "/home/azmeuk/dev/wtforms/.tox/py38/lib/python3.8/site-packages/wtforms/meta.py", line 59, in render_field
    return field.widget(field, **render_kw)
  File "/home/azmeuk/dev/wtforms/.tox/py38/lib/python3.8/site-packages/wtforms/widgets/core.py", line 306, in __call__
    for val, label, selected in field.iter_choices():
  File "/home/azmeuk/dev/wtforms/.tox/py38/lib/python3.8/site-packages/wtforms/fields/core.py", line 559, in iter_choices
    for value, label in self.choices:
ValueError: too many values to unpack (expected 2)

too many values to unpack (expected 2)
```

### Environment

* Python version: 3.8
* wtforms version: 2.3.1
