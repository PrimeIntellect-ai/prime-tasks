[Bug] direct set app.ext.config not working
**Describe the bug**
set template search pathes via
```python
app.config.TEMPLATING_PATH_TO_TEMPLATES = xxx
# OR
app.ext.config.TEMPLATING_PATH_TO_TEMPLATES = xxx
```
not working, sanic just use default `templates` dir
exception log
```
Traceback (most recent call last):
  File "<frozen importlib._bootstrap>", line 991, in _find_and_load
  File "<frozen importlib._bootstrap>", line 975, in _find_and_load_unlocked
  File "<frozen importlib._bootstrap>", line 671, in _load_unlocked
  File "<frozen importlib._bootstrap_external>", line 843, in exec_module
  File "<frozen importlib._bootstrap>", line 219, in _call_with_frames_removed
  File "/Users/chendx/xxx/server/__init__.py", line 1, in <module>
    from .app import PigaiZiApp
  File "/Users/chendx/xxx/server/app.py", line 2, in <module>
    from .demo_handler import *
  File "/Users/chendx/xxx/server/demo_handler.py", line 8, in <module>
    @app.ext.template('demo.jinja2')
  File "/Users/chendx/anaconda3/envs/pigai/lib/python3.8/site-packages/sanic_ext/bootstrap.py", line 151, in template
    return self.templating.template(template_name, **kwargs)
  File "/Users/chendx/anaconda3/envs/pigai/lib/python3.8/site-packages/sanic_ext/extensions/templating/engine.py", line 30, in template
    template = self.environment.get_template(file_name)
  File "/Users/chendx/anaconda3/envs/pigai/lib/python3.8/site-packages/jinja2/environment.py", line 883, in get_template
    return self._load_template(name, self.make_globals(globals))
  File "/Users/chendx/anaconda3/envs/pigai/lib/python3.8/site-packages/jinja2/environment.py", line 857, in _load_template
    template = self.loader.load(self, name, globals)
  File "/Users/chendx/anaconda3/envs/pigai/lib/python3.8/site-packages/jinja2/loaders.py", line 115, in load
    source, filename, uptodate = self.get_source(environment, name)
  File "/Users/chendx/anaconda3/envs/pigai/lib/python3.8/site-packages/jinja2/loaders.py", line 197, in get_source
    raise TemplateNotFound(template)
jinja2.exceptions.TemplateNotFound: demo.jinja2
```

**Additional context**
I check the sanic_ext source code, before custom config been set, the template extend has been inited.

### Additional contract requirements

- The `app.ext.config` route must be honored: after the templating extension is initialized, `app.ext.config.TEMPLATING_PATH_TO_TEMPLATES` must equal the value configured on `app.config.TEMPLATING_PATH_TO_TEMPLATES`.
