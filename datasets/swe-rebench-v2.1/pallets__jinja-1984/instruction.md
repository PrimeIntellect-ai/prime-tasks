The `int` filter throws `OverflowError` when the incoming string looks like scientific notation
So I'm using the `int` filter with a default of `None` to filter out list items that look like numbers. It worked with the test data but broke as I tried to use it for more.

Having `{{ '31e1170' | int }}` should be the minimum repro. And adding any non-default `base` will probably yield the same behavior.

Context: I'm improving a Towncrier template to allow for non-number references (such as commit messages) to be used (and linked) in changelogs. For this, I need to extract parts of the original list of things (that come from filenames — this is a part of the Towncrier logic; it's non-customizable) into separate lists — integers (PR/issue numbers), commits (strings of length 7, 8 or 40 that only have chars from the range `[0-9a-f]`) and the rest.
To perform the first filtering step, I use `| map('int', default=None) | select('integer') | map('string')`, basically turning everything non-integer into `None` and rejecting later in the chain.
Then, I reject the found numbers from the original list, and attempt checking the items for length and using the same `int` filter but with `base=16` to get things that look like commits, I put them into their own list and add the rest to yet another one.
After that, I can render those separately.

My test filenames looked differently, which is why I didn't initially catch the problem. It was luck that allowed me to stumble on this bug. I was confused at first, but then I realized that `<integer>E<integer>` is a scientific notation. When I checked the source @ https://github.com/pallets/jinja/blob/d594969/src/jinja2/filters.py#L961, it became clear whether the problem is coming from:
```pycon
>>> float('31e1170')
inf
```

Oh, and the traceback is:
```python-traceback
Traceback (most recent call last):
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/jinja2/filters.py", line 955, in do_int
    return int(value, base)
ValueError: invalid literal for int() with base 10: '31e1170'

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/runpy.py", line 194, in _run_module_as_main
    return _run_code(code, main_globals, None,
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/runpy.py", line 87, in _run_code
    exec(code, run_globals)
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/towncrier/__main__.py", line 6, in <module>
    cli()
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/click/core.py", line 1157, in __call__
    return self.main(*args, **kwargs)
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/click/core.py", line 1078, in main
    rv = self.invoke(ctx)
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/click/core.py", line 1688, in invoke
    return _process_result(sub_ctx.command.invoke(sub_ctx))
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/click/core.py", line 1434, in invoke
    return ctx.invoke(self.callback, **ctx.params)
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/click/core.py", line 783, in invoke
    return __callback(*args, **kwargs)
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/towncrier/build.py", line 123, in _main
    return __main(
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/towncrier/build.py", line 234, in __main
    rendered = render_fragments(
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/towncrier/_builder.py", line 303, in render_fragments
    res = jinja_template.render(
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/jinja2/environment.py", line 1301, in render
    self.environment.handle_exception()
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/jinja2/environment.py", line 936, in handle_exception
    raise rewrite_traceback_stack(source=source)
  File "<template>", line 18, in top-level template code
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/jinja2/async_utils.py", line 45, in wrapper
    return normal_func(*args, **kwargs)
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/jinja2/filters.py", line 1324, in sync_do_list
    return list(value)
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/jinja2/filters.py", line 1467, in sync_do_map
    for item in value:
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/jinja2/filters.py", line 1764, in select_or_reject
    for item in value:
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/jinja2/filters.py", line 1468, in sync_do_map
    yield func(item)
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/jinja2/filters.py", line 1712, in func
    return context.environment.call_filter(
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/jinja2/environment.py", line 564, in call_filter
    return self._filter_test_common(
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/jinja2/environment.py", line 545, in _filter_test_common
    return func(*args, **kwargs)
  File "/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/jinja2/filters.py", line 961, in do_int
    [HIDDEN]
OverflowError: cannot convert float infinity to integer
```
_(https://github.com/aio-libs/multidict/actions/runs/7360938745/job/20037695667#step:8:103)_

This is the template change for more context: https://github.com/aio-libs/multidict/commit/946e61a5410524fe2572ffa94cc22369cdf84a58#diff-6b766c7833e9e98b72d0413f3b72569683a45bed7406bd31900466a8704205e5R19

Solution?
[HIDDEN]

Environment:

- Python version: 3.8.18 (which shouldn't matter)
- Jinja version: unclear from the logs, likely the last one on PyPI as of today — it seems like the implementation on the current `main` has this bug, anyway

### Additional contract requirements

- When scientific-notation input causes the `int` filter’s conversion fallback to overflow, the filter must return its configured default rather than propagate `OverflowError`.
