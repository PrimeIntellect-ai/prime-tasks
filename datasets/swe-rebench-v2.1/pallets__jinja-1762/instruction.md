Can't use a test decorated with `@pass_context` in `select`
When used from `select`, tests that are decorated with `@pass_context` fail with the error:

> jinja2.exceptions.TemplateRuntimeError: Attempted to invoke a context test without context.

For example:

```python
from jinja2 import Environment, pass_context

def main():
    env = Environment()
    env.tests["foo"] = is_foo
    output = env.from_string("""

    works: {{ "foo" is foo }}

    {%- for x in ["one", "foo" ] | select("foo") %}
    fails: {{ x }}
    {%- endfor %}

    """).render({})
    print(output)


@pass_context
def is_foo(ctx, s):
    return s == "foo"


if __name__ == "__main__":
    main()
```

Environment:

- Python version: 3.10
- Jinja version: 3.0.3
