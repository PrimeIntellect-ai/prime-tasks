A different approach for `filters`
Hi, first of all, thanks for the useful library.

I want to perform some _cleaning_ in some fields, for example, remove several `\n` in a row or strip some whitespaces. The _cleanest_ way I found so far was to use `filters` in the field definition. This is not bad, but for instance, the method `clean_field()` that will be used as a filter can not be in the field container class (the form class) and only receive one argument (the field data). So I need to add the function globally or static in another class. Something like this:

```python
def clean_my_field(data):
    # remove unnecessary blank lines

class MyForm(Form):
    my_field = TextAreaField(..., filters=[clean_my_field])
```

Is there a better way to do this? I was expecting something like, I can define inside the form class a method:

```python
class MyForm(Form)
    ...
    def filter_my_field(self, data):
        # remove the unnecessary blank lines
```

and that every method called `filter_<field_name>` will be called automatically by either `Form.process()` method or a similar.

Does this make any sense? I will be willing to implement this and provide tests but I'm not sure if this is wanted.

Thanks for your hard work with WTF :)
