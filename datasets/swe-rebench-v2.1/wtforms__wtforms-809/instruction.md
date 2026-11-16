Breaking Change between 2.3 and 3.0 on SelectField(validate_choice=False)
### Actual Behavior

```python
>>> import wtforms
>>> class F(wtforms.Form):
...     foo = wtforms.SelectField(validate_choice=False)
>>> f = F()
>>> f.validate()
Traceback (most recent call last):
  File "scratch_27.py", line 7, in <module>
    f.validate()
  File "venv/lib/python3.8/site-packages/wtforms/form.py", line 329, in validate
    return super().validate(extra)
  File "venv/lib/python3.8/site-packages/wtforms/form.py", line 146, in validate
    if not field.validate(self, extra):
  File "venv/lib/python3.8/site-packages/wtforms/fields/core.py", line 231, in validate
    self.pre_validate(form)
  File "venv/lib/python3.8/site-packages/wtforms/fields/choices.py", line 136, in pre_validate
    raise TypeError(self.gettext("Choices cannot be None."))
TypeError: Choices cannot be None.
```

A quick fix consists in adding `choices=[]` to the SelectedField:
```
>>> class F(wtforms.Form):
...     foo = wtforms.SelectField(choices=[], validate_choice=False)
```
### Expected Behavior

As mentioned in the title, I wasn't expecting a breaking change on that point, as it wasn't in the changelog. I wasn't even expecting a change at all:

```python
>>> import wtforms
>>> class F(wtforms.Form):
...     foo = wtforms.SelectField(validate_choice=False)
>>> f = F()
>>> f.validate()  # no erros
```

### Environment

* Python version: 3.8
* wtforms version: 3.0.1



I am unsure if you'd rather add this to the documentation somewhere, or fix the compatibility break (which seems quite easy).
I've found a similar issue: https://github.com/wtforms/wtforms/issues/606; except that I'm expecting to be able to not provide any choices at all here.
