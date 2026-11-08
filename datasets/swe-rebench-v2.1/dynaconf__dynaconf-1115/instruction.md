BoxKeyError when using setdefault
The following code raises `BoxKeyError`.
```python
my_flask_dynaconf.init_app(app)
asdf = app.config.setdefault("ASDF", {})
asdf.setdefault("qwer", "zxcv")
qwer = app.config["ASDF"]["qwer"]
```

The reason for bringing this up is because the Flask extension Flask-Alembic uses this code pattern.

Please see [the Flask-Alembic source code](https://github.com/pallets-eco/flask-alembic/blob/3.1.0/src/flask_alembic/extension.py).
On line 150 and 151 `script_location` is defined.
On line 215 `script_location` is accessed, and this is where Dynaconf raises `BoxKeyError`.

It would be good if these libraries could be used at the same time.
Is there anything that could be changed in Dynaconf to accommodate for this pattern? Or is this pattern incompatible with Dynaconf?

It is possible to workaround the issue, by moving the call to Flask-Alembic's `init_app` so that it occurs before the call to Dynaconf's Flask `init_app`.
But that probably does not count as a proper solution. Ideally, Dynaconf's Flask `init_app` should be the first one to be called, so that config is loaded before everything else.

### Additional contract requirements

- When Dynaconf is initialized for a Flask application with `compatibility_mode=True` (for example `FlaskDynaconf(app, compatibility_mode=True)`), nested mappings must be usable through plain mapping subscription: a nested mapping created through `app.config.setdefault` and populated with another `setdefault` must be retrievable as `app.config["ASDF"]["qwer"]`, returning the value that was set in the nested mapping.
- The same nested configuration pattern must work in compatibility mode when a Flask extension initializes after Dynaconf; callers must not need to initialize that extension before Dynaconf.
