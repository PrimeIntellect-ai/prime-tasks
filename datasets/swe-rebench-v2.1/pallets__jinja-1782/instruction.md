unique filter does not work when chain with a filter that returns async generator
`unique()` filter does not work when chain with a filter that returns async generator

Environment:

- Python version: 3.11
- Jinja version: 3.1.2

The template:
```
{%- set commit_authors = commits | rejectattr("author", "eq", "mergify[bot]") | unique(false, "email_author")| list -%}
```

The backtrace:
```
  File "xxxxxx.py", line 2314, in render_template
    return await env.from_string(template).render_async(**infos)
  File "jinja2/environment.py", line 1324, in render_async
    return self.environment.handle_exception()
  File "jinja2/environment.py", line 936, in handle_exception
    raise rewrite_traceback_stack(source=source)
  File "jinja2/environment.py", line 1321, in <listcomp>
    [n async for n in self.root_render_func(ctx)]  # type: ignore
  File "<template>", line 7, in top-level template code
  File "jinja2/async_utils.py", line 65, in auto_await
    return await t.cast("t.Awaitable[V]", value)
  File "jinja2/filters.py", line 1329, in do_list
    return await auto_to_list(value)
  File "jinja2/async_utils.py", line 84, in auto_to_list
    return [x async for x in auto_aiter(value)]
  File "jinja2/async_utils.py", line 84, in <listcomp>
    return [x async for x in auto_aiter(value)]
  File "jinja2/async_utils.py", line 77, in auto_aiter
    for item in t.cast("t.Iterable[V]", iterable):
  File "jinja2/filters.py", line 437, in do_unique
    for item in value:
TypeError: 'async_generator' object is not iterable
```
