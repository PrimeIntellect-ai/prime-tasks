Add forceescape filter
Seems that escaping of `caller()` no longer works with switched off default auto escaping and returns raw html.

I'm not sure is it intentional, or is it a bug.

``` jinja
{% macro example() %}
<pre><code>{{ caller()|escape }}</code></pre>
{% endmacro %}

{% call example() %}
First line <br> second line
{% endcall %}
```

should return

``` html
First line &lt;br&gt; second line
```

but returns

``` html
First line
second line
```

### Additional contract requirements

- A template filter named `forceescape` is available. It HTML-escapes its input, even when the input is already marked safe.
- Applying `forceescape` to caller-block content (for example `{{ caller() | forceescape }}`) must produce HTML-escaped markup when automatic escaping is disabled, so `<br>` in the caller body is output as `&lt;br&gt;`.
