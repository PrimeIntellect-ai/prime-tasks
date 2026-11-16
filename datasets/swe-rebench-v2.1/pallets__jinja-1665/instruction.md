What's wrong with this Jinja template when using {% elif %}
I have the following **Jinja** template:

```jinja
{% if new_data_set_created is defined %}
    {% if new_data_set_created == True %}
        The new image data set <strong>{{ form_data["data_set_name"] }}</strong> has been created.
        {% set form_data = {"data_set_name": "", "client": "", "project": ""} %}
    {% else %}
        The new image data set <strong>{{ form_data["data_set_name"] }}</strong> could not be created.<br />
    {% endif %}
{% elif deleted_data_set is defined %}
    The image data set <strong>{{ deleted_data_set }}</strong> has been deleted from DB and from disk.
    {% set form_data = {"data_set_name": "", "client": "", "project": ""} %}
{% else %}
    {% set form_data = {"data_set_name": "", "client": "", "project": ""} %}
{% endif %}
```

However, when rendering this template via **Flask** I get the error message that `form_data` in line 3 of this code section is undefined (which is not the case, I double-checked that):

    jinja2.exceptions.UndefinedError: 'form_data' is undefined

Now when I remove the `elif` block from that code section above (i.e. lines 8-10) then the very same template does work again and line 3 does not lead to an error any more.

I am calling this template like so:

```python
return render_template(
    "image-data-sets.html",
    new_data_set_created=True,
    form_data=request.form,
    data_sets=ImageDataSet.query.all(),
    clients=clients,
)
```

I double-checked that `request.form` (and thus `form_data` within the template) is not `None`. And as said, I don't make any changes to this call, I just remove those lines from the template and then it's working.

So my question: Why does removing the `elif` block fix this issue, and why is this error raised in the first place? What's wrong with my `if-elif-else-endif` block? Is this a bug or am I missing something?
