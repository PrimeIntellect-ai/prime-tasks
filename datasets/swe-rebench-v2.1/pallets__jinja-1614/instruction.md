custom filters with async_true enabled giving 'coroutine' object is not subscriptable error
**Description**
When applying a custom (synchronous) filter to a passed in object in a for loop, we are getting a `TypeError: 'coroutine' object is not subscriptable` Error. It seems to be an extension of this issue: https://github.com/pallets/jinja/issues/1141


**Reproduction**
Very similar to the above issue, you can minimally reproduce like:

`{% for item in (a.b|add_two(5))[:1] %}{{ item }}{% endfor %}`
with a jinja environment of:
```
jinja_env = jinja2.Environment(enable_async=True)
jinja_env.filters.update({'add_two': lambda x, y: [i+y for i in x]})
```

rendering with `a=dict(b=[1,2,3])` will result in the `'coroutine' object is not subscriptable`

We tried removing the parenthesis around the method call:
`{% for item in a.b|add_two(5)[:1] %}{{ item }}{% endfor %}`
but that results in a different `jinja2.exceptions.TemplateSyntaxError: expected token 'end of statement block', got '['` error


**Environment**

- Python version: 3.9
- Jinja version: 3.0.3
