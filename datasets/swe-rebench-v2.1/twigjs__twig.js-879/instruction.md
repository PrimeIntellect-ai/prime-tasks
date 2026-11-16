accessing an array element with a colon
I'm passing in a hydra json response, which includes an element with a key of 'hydra:member'.

My twig template is

```twig
<h3>
    {{ data['@type'] }}
</h3>
{% for d in data['hydra:member'] %}
{{ d.id }}
{% endfor %}
```

This throws an error

TwigException: Twig.expression.type.array.start cannot follow a Twig.expression.type.variable at template:4 near '[...'
 ERROR  Failed to compile with 1 errors                                                                                                                                                       Syntax Error: Unexpected token u in JSON at position 0
    at JSON.parse (<anonymous>)

My solution is to set a temporary variable and use it, but I'm wondering if there's a better way, or if this can be fixed.

```twig
{% set hack = 'hydra:member' %}
{% for d in data[hack] %}
{{ d.id }}
{% endfor %}
```

Thanks.  I think this library rocks.
