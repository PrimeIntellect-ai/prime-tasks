validators.NumberRange doesn't handle NaN
Validating a `DecimalField` with a `NumberRange` validator throws a `decimal.InvalidOperation` exception when the value of the field is NaN. I would expect validation to fail instead
```
File "/usr/local/lib/python3.6/dist-packages/wtforms/form.py", line 310, in validate
  return super(Form, self).validate(extra)
File "/usr/local/lib/python3.6/dist-packages/wtforms/form.py", line 152, in validate
  if not field.validate(self, extra):
File "/usr/local/lib/python3.6/dist-packages/wtforms/fields/core.py", line 206, in validate
  stop_validation = self._run_validation_chain(form, chain)
File "/usr/local/lib/python3.6/dist-packages/wtforms/fields/core.py", line 226, in _run_validation_chain
  validator(form, self)
File "/usr/local/lib/python3.6/dist-packages/wtforms/validators.py", line 134, in __call__
  if data is None or (self.min is not None and data < self.min) or
decimal.InvalidOperation: [<class 'decimal.InvalidOperation'>]
```
