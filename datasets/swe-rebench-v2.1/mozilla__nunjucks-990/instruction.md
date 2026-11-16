Set blocks prints its content
In 3.0.0 set block for some reason immediately prints it content.

``` jinja2
{% set test %}
TEST
{% endset %}

result: {{ test }}
```

outputs

``` html
TEST

result:
```

As you can see, set print itself immediately, and `{{ test }}` call doesn't work.

Should it be like that?
