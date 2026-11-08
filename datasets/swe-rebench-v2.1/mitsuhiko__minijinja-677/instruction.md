Calling `{% break %}` on an iterator results in a lost value
## Description
The `{% break %}` statement consumes an item of the iterator that you can't have access to anymore. If you start consuming the iterator again, that value doesn't appear, but instead it continues with the next value.

This wasn't the case in the Python implementation of Jinja2.

## Reproduction steps

You can see in the example below that even though the iterator was `0..10` the item `6` is swallowed after calling `{% break %}`.

```rs
use std::fs::File;

use minijinja::{Environment, Value};

fn main() {
    let mut env = Environment::new();
    env.add_template("template", include_str!("template.jinja"))
        .unwrap();
    let template = env.get_template("template").unwrap();

    let out = File::create("test.txt").unwrap();

    template
        .render_to_write(
            minijinja::context! { items => Value::make_one_shot_iterator(0..10)},
            out,
        )
        .unwrap();
}
```

```jinja
{%- for item in items -%}
    {%- if item == 5 -%}
        {{ item }}
        {% break %}
    {%- endif -%}

    {{ item }}
{% endfor %}
newloop

{% for item in items -%}
    {{ item }}
{% endfor %}
```

output:
```
0
1
2
3
4
5

newloop

7
8
9
```

Additional helpful information:

- Version of minijinja: `2.6.0` with the `loop_controls` feature
- Version of rustc: `v1.85.0-nightly`
- Operating system and version: `Ubuntu 24.04`

## What did you expect
I would expect the value `6` in the example above to be part of the second loop.
In other words, the `break` statement shouldn't have swallowed it.
