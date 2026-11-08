Generate methods to render each Block independently?
My use case with [HTMX](https://htmx.org) is that a response may either include the full page (extending `base.html`) or just a single block `content` depending on a request header. Right now, using Minijinja, this is implemented centrally in a custom middleware which decides what to render.

I'd love to switch to Rinja, but right now this is not possible without having two versions of every struct, modifying every endpoint to either return the full- or the partial template struct, with the latter one annotated with `#[attribute(block = "content")]`.

Would you consider extending the `Template` derive macro to be able to generate methods on the struct which allow rendering each block individually? I'm thinking of something like:

```jinja2
{% block title %}Hello {{title}}{% endblock %}
{% block content %}...{% endblock %}
```


```rust
#[derive(Template)]
#[attribute(file = "foo.html", generate_block_methods = "true")]
struct Foo {
    title: String
}

// Generated

impl Template for Foo {..}

impl Foo {
    fn render_block_title(&self) -> Result<String> { ... }
    fn render_block_content(&self) -> Result<String> { ... }
}
```

The methods could even be used in the existing `render` methods (possibly annotated `#[inline]`) to avoid generating redundant code.

Another approach could be extending `Template` and `DynTemplate` with a `fn render_block(&self, block: &str) -> ...` method.

### Additional contract requirements

Templates that expose block rendering accept a `blocks` list in the `Template` derive attribute. For each listed block named `name`, the derived value exposes `as_name()`, which returns a renderable template for that block. The same derived value must also render the full template, and block rendering must work for a block inherited from an extended template.
