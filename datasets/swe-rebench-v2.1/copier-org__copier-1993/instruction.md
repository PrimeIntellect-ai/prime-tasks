Copier 9.5.0 fails to provide `data` in rendering context
### Describe the problem

I use copier programmatically to render a template. Some variables used in templates are asked from the user, while others are inserted by the code. The variables we want to insert into the template are passed in `data` to `copier.Worker`. Here's an example:


```python3
data = {'my_injected_variable': '17'}

with copier.Worker(
        src_path=str(tpl_dir),
        dst_path=dst_path,
        unsafe=True,
        data=data,
        quiet=True,
        defaults=False,
    ) as worker:
        worker.jinja_env.add_extension("my_package.jinja_ext.ContextUpdater")
        worker.run_copy()
```

I have a Jinja extension that extends this context even further (`my_package.jinja_ext.ContextUpdater`). It looks like this:

```python3
from copier_templates_extensions import ContextHook

class ContextUpdater(ContextHook):
    update = False

    def hook(self, context: dict):
        """Modify the template context."""
        from pprint import pprint
        pprint(context)
        assert "my_injected_variable" in context
        context["my_other_stuff"] = context["my_injected_variable"] + "something"
```

In copier 9.4, I get the following `context` and everything works just fine:

```python3
{'_copier_answers': {'_src_path': 'REMOVED'},
 '_copier_conf': {'answers': {'hidden': set(),
                              'init': {'my_injected_variable': '17'},
                              'last': {},
                              'metadata': {'_src_path': 'REMOVED'},
                              'user': {},
                              'user_defaults': {}},
                  'answers_file': PosixPath('.copier-answers.yml'),
                  'cleanup_on_error': True,
                  'conflict': 'inline',
                  'context_lines': 3,
                  'data': {'my_injected_variable': '17'},
                  'defaults': False,
                  'dst_path': PosixPath('REMOVED'),
                  'exclude': (),
                  'os': 'linux',
                  'overwrite': False,
                  'pretend': False,
                  'quiet': True,
                  'sep': '/',
                  'settings': Settings(defaults={}, trust=set()),
                  'skip_answered': False,
                  'skip_if_exists': (),
                  'skip_tasks': False,
                  'src_path': PosixPath('REMOVED'),
                  'unsafe': True,
                  'use_prereleases': False,
                  'user_defaults': {},
                  'vcs_ref': None,
                  'vcs_ref_hash': None},
 '_copier_python': '/usr/bin/python3.9',
 '_folder_name': 'ibm-systems-cte2-tools-spider',
 '_src_path': 'REMOVED',
 'cycler': <class 'jinja2.utils.Cycler'>,
 'dict': <class 'dict'>,
 'joiner': <class 'jinja2.utils.Joiner'>,
 'lipsum': <function generate_lorem_ipsum at 0x7f6460c55670>,
 'make_secret': <function _make_secret at 0x7f645cb9b3a0>,
 'namespace': <class 'jinja2.utils.Namespace'>,
 'now': <function _now at 0x7f645cabd280>,
 'pathjoin': <function Worker.jinja_env.<locals>._pathjoin at 0x7f6457efb820>,
 'range': <function safe_range at 0x7f645cd40ca0>,
 'my_injected_variable': '17'}
```

Note the top-level key `context['my_injected_variable']`!


In copier 9.5, I get the following `context`:

```python3
{'_copier_answers': {'_src_path': 'REMOVED'},
 '_copier_conf': {'answers_file': PosixPath('.copier-answers.yml'),
                  'cleanup_on_error': True,
                  'conflict': 'inline',
                  'context_lines': 3,
                  'data': {'my_injected_variable': '17'},
                  'defaults': False,
                  'dst_path': PosixPath('REMOVED'),
                  'exclude': (),
                  'os': 'linux',
                  'overwrite': False,
                  'pretend': False,
                  'quiet': True,
                  'sep': '/',
                  'settings': Settings(defaults={}, trust=set()),
                  'skip_answered': False,
                  'skip_if_exists': (),
                  'skip_tasks': False,
                  'src_path': PosixPath('REMOVED'),
                  'unsafe': True,
                  'use_prereleases': False,
                  'user_defaults': {},
                  'vcs_ref': None,
                  'vcs_ref_hash': None},
 '_copier_python': '/usr/bin/python3.9',
 '_external_data': <copier.main._LazyDict object at 0x7f242e2bf130>,
 '_folder_name': 'ibm-systems-cte2-tools-spider',
 'cycler': <class 'jinja2.utils.Cycler'>,
 'dict': <class 'dict'>,
 'joiner': <class 'jinja2.utils.Joiner'>,
 'lipsum': <function generate_lorem_ipsum at 0x7f243b869550>,
 'make_secret': <function _make_secret at 0x7f24337953a0>,
 'namespace': <class 'jinja2.utils.Namespace'>,
 'now': <function _now at 0x7f24336b7040>,
 'pathjoin': <function Worker.jinja_env.<locals>._pathjoin at 0x7f2432b15940>,
 'range': <function safe_range at 0x7f2433937b80>}
```

Now the top-level key `context['my_injected_variable']` is missing, causing the problems I'm seeing.

This new new behavior got introduced in https://github.com/copier-org/copier/pull/1880.

It feels like a regression, but maybe I was just using the API wrongly before. What's the new way of achieving what I'm looking for?


### Operating system

Linux

### Operating system distribution and version

RHEL 8

### Copier version

9.5.0

### Python version

cpython 3.9

### Installation method

pipx+pypi

### Additional contract requirements

- The returned mapping contains the values supplied through `Worker(data=...)` as top-level keys, so a value passed as `data={"my_injected_variable": "17"}` is available as `context["my_injected_variable"]`.
- The returned mapping also contains the reserved keys `_copier_answers`, `_copier_conf`, `_folder_name` and `_copier_python`.
