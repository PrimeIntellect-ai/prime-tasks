Template globals are not accessible within imports w/ enable_async
Template globals are not applied correctly when using the `enable_async` environment flag.

When used normally, template globals can be used within imported macros.

With `enable_async=True`, template globals can only be accessed in macros within the immediate template.

### Example script:

```python
from jinja2 import Environment
from jinja2.loaders import DictLoader
import asyncio

templates = {
    "child.html": """\
{% extends default_layout or 'default.html' %}
{% from 'helpers.html' import imported_get_value%}
{% macro get_value() %}{{value}}{% endmacro %}
]{% block body %}
    {{ get_value() }}
    {{ imported_get_value() }}
{% endblock %}
""",
    "default.html": """\
<!doctype html>
<title>{{ value }}</title>
{% block body %}{% endblock %}
""",
    "helpers.html": """\
{% macro imported_get_value() %}{{value}}{% endmacro %}
""",
}


def sync_main():
    env = Environment(loader=DictLoader(templates))
    tmpl = env.get_template("child.html", globals={"value": "hello"})
    print(tmpl.render())


async def async_main():
    env = Environment(loader=DictLoader(templates), enable_async=True)
    tmpl = env.get_template("child.html", globals={"value": "hello"})
    print(await tmpl.render_async())


if __name__ == "__main__":
    print("---- SYNC ----")
    sync_main()
    print("---- ASYNC ----")
    asyncio.run(async_main())
```

### Output

```
---- SYNC ----
<!doctype html>
<title>hello</title>

    hello
    hello

---- ASYNC ----
<!doctype html>
<title>hello</title>

    hello

```

I expected the above output to be the same for sync and async.

Environment:

- Python version: 3.9.6
- Jinja version: 3.0.1
