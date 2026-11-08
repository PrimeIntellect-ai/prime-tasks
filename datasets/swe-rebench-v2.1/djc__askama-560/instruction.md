escape filter does not escape when escape attribute is set to none
Perhaps this is just a documentation issue but following the recursive macro workaround described in https://github.com/djc/askama/issues/105#issuecomment-483937352 via #308 I annotated my struct as follows:

```rust
#[derive(Debug, Template)]
#[template(path = "topic/node.html", escape = "none")]
pub struct TopicNode {
    pub topic: Topic,
    pub children: TopicTree,
}
```

With a template that looks like this:

```jinja
<li>{{ topic.name }}</li>
{% if !children.is_empty() %}
<li>
    <ul class="tree-list">
        {% for child in children %}
            {{ child.render().unwrap() }}
        {% endfor %}
    </ul>
</li>
{% endif %}
```

I noticed that the name in the first line was no longer being escaped... not unexpected given `escape = "none"` so I tried to manually escape by doing:

```jinja
<li>{{ topic.name|escape }}</li>
```

which still did not escape the text. It seems the `E` argument of the `escape` filter is filled in with the current escaper, which in this case in `none`. I was able to work around this by defining a custom filter as follows:

```rust
pub fn html_escape<T>(v: T) -> askama::Result<MarkupDisplay<Html, T>>
    where
        T: fmt::Display,
{
    Ok(MarkupDisplay::new_unsafe(v, Html))
}
```

Which, works as expected. Anyway, [the docs](https://djc.github.io/askama/filters.html#escape--e) suggest that HTML will always be escaped so I thought it was worth opening an issue. Thanks.

### Additional contract requirements

The `escape` filter accepts an optional escaper-name argument, for example `{{ foo|escape("html") }}`. The argument is a string literal naming an escaper and selects that escaper for that filter invocation, overriding the template's configured escaper. The available escaper names are the same names accepted by the `escape` template attribute (for example `"html"` and `"none"`). In particular, in a template configured with `escape = "none"`, `{{ foo|escape("html") }}` escapes `foo` as HTML, while `{{ foo|escape("none") }}` leaves it unescaped. When the argument is omitted, `escape` uses the template’s configured escaper: thus a bare `{{ foo|escape }}` in a template configured with `escape = "none"` leaves `foo` unescaped, while a template configured with HTML escaping applies HTML escaping.
