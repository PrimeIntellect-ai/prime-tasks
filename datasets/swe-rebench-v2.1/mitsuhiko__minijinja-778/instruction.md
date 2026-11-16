`{% import "foo.html" as foo %}` doesn't work as in Jinja
## Description

In Jinja, I can import a partial using the `as foo` syntax, and then print the template using `{{ foo }}`. Minijinja however just prints `{}`.

## Reproduction steps

Runnable reproduction:

``` rust
use minijinja::Environment;

fn main() {
    let mut env = Environment::new();
    env.add_template("main.html", "{% import \"hello.html\" as hello %} {{ hello }}").unwrap();
    env.add_template("hello.html", "<p>Hello world!</p>").unwrap();

    let template = env.get_template("main.html").unwrap();
    let html = template.render(&{}).unwrap();

    println!("{}", html);
}
```

Additional helpful information:

- Version of minijinja: 2.9.0
- Version of rustc: 1.86
- Operating system and version: macOS

## What did you expect

Program prints `<p>Hello world!</p>`

## Why is this relevant?

We use this as a hack to inline SVG icons into `style` tags in Material for MkDocs:

``` jinja
{% if config.theme.icon.admonition %}
  {% set _ = namespace(style = "\x3cstyle\x3e:root{") %}
  {% for type, icon in config.theme.icon.admonition | items %}
    {% import ".icons/" ~ icon ~ ".svg" as icon %}
    {% set _.style = _.style ~
      "--md-admonition-icon--" ~ type ~ ":" ~
      "url('data:image/svg+xml;charset=utf-8," ~
        icon | replace("\n", "") | urlencode ~
      "');"
    %}
  {% endfor %}
  {% set _.style = _.style ~ "}\x3c/style\x3e" %}
  {{ _.style }}
{% endif %}
```

[Source](https://github.com/squidfunk/mkdocs-material/blob/4c0004e16b1d51511fbd3c8537394069f004ecfe/src/templates/partials/icons.html#L24-L37)
