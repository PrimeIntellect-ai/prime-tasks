Override field's name attribute?
I need compatibility with some existing HTML that uses dashes in the `name` attribute, but I have yet to find a way to override it with wtforms. [The documentation for `wtforms.fields.core.Field`](https://wtforms.readthedocs.org/en/latest/fields.html?highlight=selectmultiplefield#wtforms.fields.Field) mentions the following about `_name`:

> The name of this field, passed by the enclosing form during its construction. You should never pass this value yourself.

This makes me think that I should be able to override the name in the enclosing form. But in that case - where? Here's a failing test that shows what I'm expecting to be able to do:

``` python
import wtforms
from werkzeug.datastructures import ImmutableMultiDict


class MyForm(wtforms.Form):
    my_field_id = wtforms.IntegerField('My field', id='my-field',
                                       _name='my-field')


my_data = ImmutableMultiDict([('my-field', '2')])
my_form = MyForm(my_data)
assert my_form.my_field_id.name == 'my-field'  # Instead `my_field_id`
assert my_form.my_field_id.data == 2  # Instead `None`
```

Instead I have to use this custom field to get what I'm looking for:

``` python
import wtforms
class MyCustomIntegerField(wtforms.IntegerField):

    def __init__(self, *args, **kwargs):
        name = kwargs.pop('name', None)
        super().__init__(*args, **kwargs)
        if name:
            self.name = name
```

Am I missing something here?

### Additional contract requirements

- A field accepts a public `name` argument that sets its HTML name, overriding the name derived from the Python attribute it is declared as. The field's `name` attribute is the (possibly prefixed) HTML name and its `short_name` is the given name.
- The `name` argument is accepted when a field is declared on a form and is used for rendering and for processing submitted input, while Python-side attribute access continues to use the declared attribute name.
- `wtforms.fields.core.FieldList` accepts a `name` argument that sets the HTML name of the list container; its entries are rendered and processed under that name (for example `foo-0`).
- `wtforms.fields.core.DecimalField` accepts the same `name` argument.
