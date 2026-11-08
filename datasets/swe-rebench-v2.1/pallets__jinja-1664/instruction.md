Namespaces do not allow multi-variable assignments
Replace this comment with a clear outline of what the bug is.
-->

In Jinja we can use standard python multi-variable assignments like line 3 below, which successfully evaluates but does not confer benefits of namespaces variables.

However, line 4 below throws an error, `jinja2.exceptions.TemplateSyntaxError: expected token 'end of statement block', got ','`
```
            {% set full = namespace(id="", prev_id="") -%}
            {% for id endpoints recursive %}
              {% set prev_id, id = id, id + "/" + id -%}
              {% set full.prev_id, full.id = full.id, full.id + "/" + id -%}
            {% endfor -%}
```


Include the full traceback if there was an exception.
-->

```
Traceback (most recent call last):
  File "/home/ubuntu/.tox/dev/lib/python3.6/site-packages/flask/app.py", line 2328, in __call__
    return self.wsgi_app(environ, start_response)
  File "/home/ubuntu/.tox/dev/lib/python3.6/site-packages/flask/app.py", line 2314, in wsgi_app
    response = self.handle_exception(e)
  File "/home/ubuntu/.tox/dev/lib/python3.6/site-packages/flask/app.py", line 1760, in handle_exception
    reraise(exc_type, exc_value, tb)
  File "/home/ubuntu/.tox/dev/lib/python3.6/site-packages/flask/_compat.py", line 36, in reraise
    raise value
  File "/home/ubuntu/.tox/dev/lib/python3.6/site-packages/flask/app.py", line 2311, in wsgi_app
    response = self.full_dispatch_request()
  File "/home/ubuntu/.tox/dev/lib/python3.6/site-packages/flask/app.py", line 1834, in full_dispatch_request
    rv = self.handle_user_exception(e)
  File "/home/ubuntu/.tox/dev/lib/python3.6/site-packages/flask/app.py", line 1737, in handle_user_exception
    reraise(exc_type, exc_value, tb)
  File "/home/ubuntu/.tox/dev/lib/python3.6/site-packages/flask/_compat.py", line 36, in reraise
    raise value
  File "/home/ubuntu/.tox/dev/lib/python3.6/site-packages/flask/app.py", line 1832, in full_dispatch_request
    rv = self.dispatch_request()
  File "/home/ubuntu/.tox/dev/lib/python3.6/site-packages/flask/app.py", line 1818, in dispatch_request
    return self.view_functions[rule.endpoint](**req.view_args)
  File "/home/ubuntu/cap/endpoints/views.py", line 12, in home_page
    return Response(render_template('home.html'))
  File "/home/ubuntu/.tox/dev/lib/python3.6/site-packages/flask/templating.py", line 135, in render_template
    context, ctx.app)
  File "/home/ubuntu/.tox/dev/lib/python3.6/site-packages/flask/templating.py", line 117, in _render
    rv = template.render(context)
  File "/home/ubuntu/.tox/dev/lib/python3.6/site-packages/jinja2/environment.py", line 1090, in render
    self.environment.handle_exception()
  File "/home/ubuntu/.tox/dev/lib/python3.6/site-packages/jinja2/environment.py", line 832, in handle_exception
    reraise(*rewrite_traceback_stack(source=source))
  File "/home/ubuntu/.tox/dev/lib/python3.6/site-packages/jinja2/_compat.py", line 28, in reraise
    raise value.with_traceback(tb)
  File "/home/ubuntu/cap/templates/home.html", line 1, in top-level template code
    {% extends "index.html" %}
  File "/home/ubuntu/.tox/dev/lib/python3.6/site-packages/jinja2/environment.py", line 832, in handle_exception
    reraise(*rewrite_traceback_stack(source=source))
  File "/home/ubuntu/.tox/dev/lib/python3.6/site-packages/jinja2/_compat.py", line 28, in reraise
    raise value.with_traceback(tb)
  File "/home/ubuntu/cap/templates/index.html", line 89, in template
    {% set full.prev_id, full.id = full.id, full.id + "/" + id -%}
jinja2.exceptions.TemplateSyntaxError: expected token 'end of statement block', got ','
```

Environment:

- Python version: 3.6.9
- Jinja version: 2.11.3
