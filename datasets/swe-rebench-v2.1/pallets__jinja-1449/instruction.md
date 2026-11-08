AssertionError: Tried to resolve a name to a reference that was unknown to the frame
Hi folks! Thanks for shipping a new release with fantastic type annotations - very much looking forward to that. :)
I've just tried upgrading, but I'm running in the following regression on the way:

`repro.jinja2`
```jinja
{% set output %}
    {% for x in [1,2,3] %}
        hello
    {% endfor %}
{% endset %}
{{ output }}
```

Jinja 2.11.3

```
        hello
        hello
        hello
```

Jinja 3.0.0

```
Traceback (most recent call last):
  File "/home/user/venv/bin/j2", line 8, in <module>
    sys.exit(main())
  File "/home/user/venv/lib/python3.9/site-packages/j2cli/cli.py", line 202, in main
    output = render_command(
  File "/home/user/venv/lib/python3.9/site-packages/j2cli/cli.py", line 186, in render_command
    result = renderer.render(args.template, context)
  File "/home/user/venv/lib/python3.9/site-packages/j2cli/cli.py", line 85, in render
    return self._env \
  File "/home/user/venv/lib/python3.9/site-packages/jinja2/environment.py", line 996, in get_template
    return self._load_template(name, globals)
  File "/home/user/venv/lib/python3.9/site-packages/jinja2/environment.py", line 957, in _load_template
    template = self.loader.load(self, name, self.make_globals(globals))
  File "/home/user/venv/lib/python3.9/site-packages/jinja2/loaders.py", line 137, in load
    code = environment.compile(source, name, filename)
  File "/home/user/venv/lib/python3.9/site-packages/jinja2/environment.py", line 749, in compile
    source = self._generate(source, name, filename, defer_init=defer_init)
  File "/home/user/venv/lib/python3.9/site-packages/jinja2/environment.py", line 677, in _generate
    return generate(  # type: ignore
  File "/home/user/venv/lib/python3.9/site-packages/jinja2/compiler.py", line 116, in generate
    generator.visit(node)
  File "/home/user/venv/lib/python3.9/site-packages/jinja2/visitor.py", line 40, in visit
    return f(node, *args, **kwargs)
  File "/home/user/venv/lib/python3.9/site-packages/jinja2/compiler.py", line 887, in visit_Template
    self.blockvisit(node.body, frame)
  File "/home/user/venv/lib/python3.9/site-packages/jinja2/compiler.py", line 448, in blockvisit
    self.visit(node, frame)
  File "/home/user/venv/lib/python3.9/site-packages/jinja2/visitor.py", line 40, in visit
    return f(node, *args, **kwargs)
  File "/home/user/venv/lib/python3.9/site-packages/jinja2/compiler.py", line 1581, in visit_AssignBlock
    self.pop_assign_tracking(frame)
  File "/home/user/venv/lib/python3.9/site-packages/jinja2/compiler.py", line 812, in pop_assign_tracking
    ref = frame.symbols.ref(name)
  File "/home/user/venv/lib/python3.9/site-packages/jinja2/idtracking.py", line 80, in ref
    raise AssertionError(
AssertionError: Tried to resolve a name to a reference that was unknown to the frame ('x')
```

I've skimmed the Changelog, but couldn't identify anything that may point me in the right direction. The traceback is a bit above my head. Please let me know if I can help with anything else! 😃

#### *Edit:* Workaround

It's possible to convince Jinja2 that everything is ok by first defining the inner loop variable:

```jinja
{% set x = None %}
{% set output %}
    {% for x in [1,2,3] %}
        hello
    {% endfor %}
{% endset %}
{{ output }}
```

Environment:

- Python version: Python 3.9.4
- Jinja version: 3.0.0
