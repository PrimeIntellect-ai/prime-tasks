DateTimeLocalField should support `T` separator
The [MDN documentation](https://developer.mozilla.org/en-US/docs/Web/HTML/Date_and_time_formats#local_date_and_time_strings) we can read that:

>When you set the value of a datetime-local input, the string is normalized into a standard form. Normalized datetime strings always use the letter "T" to separate the date and the time, and the time portion of the string is as short as possible. This is done by leaving out the seconds component if its value is :00.

However, wtforms currently does not support that `T` separator:

```python
>>> import wtforms
>>> from tests.common import DummyPostData
>>> class F(wtforms.Form):
...     dtl = wtforms.DateTimeLocalField()
>>> F(DummyPostData({"dtl": "2020-10-10 10:10:10"})).dtl.data
datetime.datetime(2020, 10, 10, 10, 10, 10)
>>> F(DummyPostData({"dtl": "2020-10-10T10:10:10"})).dtl.data
>>>
```

I suggest we support that `T` separator out of the box. It also seems this is the separator by default in Firefox.

Might be related with #435
