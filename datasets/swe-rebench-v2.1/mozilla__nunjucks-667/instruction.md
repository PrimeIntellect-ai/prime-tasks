Macros can see variables from their caller's scope.
In nunjucks currently, macros can see variables from their caller's scope, that were not explicitly passed in as arguments. E.g. the following template:

```
{% macro one(var) %}
  {{ two() }}
{% endmacro %}

{% macro two() %}
  {{ var }}
{% endmacro %}

{{ two("hello") }}
```

renders `hello`; macro `two` is able to see the value of `var` from macro `one`, even though it is not passed in as an argument.

 In Jinja2 that template renders nothing.

I consider the Jinja2 behavior correct, and the nunjucks behavior a bug.

It is possible, however, that people have written templates that depend on this bug to render correctly. For that reason, I'll probably fix it in 3.0 rather than in the 2.x series.
