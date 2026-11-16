Support parameter abbreviation on Flask and Django plugins
### Discussed in https://github.com/dynaconf/dynaconf/discussions/847

<div type='discussions-op-text'>

<sup>Originally posted by **kssflow** December 27, 2022</sup>

Hello everyone! (happy new year in advance 🎉)
First of all, really appreciate for maintaining this invaluable, literally amazing open source project. 👏😸


I consult to Flask documentating saying "dynaconf" is one of (recommended) solutions for configuration management.
So I have given a shot to this library with carefully reading the docs and typing code.
But the more I do my best to handle(solve) the problem the more I totally lost in frustration.

For example, the doc says `envvar_prefix` makes the prefix of environment variable.

```python

from flask import Flask
from dynaconf import FlaskDynaconf

app = Flask(__name__)
FlaskDynaconf(app, envvar_prefix="PEANUT")

```

It doesn't work... but if I change the `envvar_prefix` to `envvar_prefix_for_dynaconf`, it works finally.

**Does doc is wrong?**
(I hope that it's not doc but me makes problem)
If docs are wrong, there seems to be INCONSISTENCY related to Flask Integration part...

python code

```python

# main.py
# working code

from flask import Flask, render_template, current_app
from dynaconf import FlaskDynaconf

app = Flask(__name__, template_foler=templates")
FlaskDynaconf(app,
   load_dotenv=True,
   envvar_prefix_for_dynaconf="DAMNIT"  # 🔴 doc say "envvar_prefix" but that doesn't work
)

@app.route("/", methods=["GET"])
def index():
    settings = current_app.config
   return render_template("index.html.jinja", settings=settings")

```

jinja(html) code

```html

<!DOCTYPE html>
<html lang="en">

<head>
    <meta charset="UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Document</title>
</head>

<body>
    <h1>HELP ME!!</h1>
    <div style="border: 1px solid red; width: 100px; height: 100px;">
        {{ settings.APPNAME }}
    </div>
    <div>
        {% if settings %}
            <dl>
            {% for key, value in settings.items() %}
                <dt>{{ key }}</dt>
                <dd>{{ value }}</dd>
            {% endfor %}
            </dl>
        {% endif %}
    </div>
</body>

</html>

```

.env
```bash

FLASK_APPNAME=APP NAME FROM FLASK_APPNAME
DAMNIT_APPNAME=APP NAME FROM DAMNIT_APPNAME

```

🟢 results with `envvar_prefix_for_dynaconf=DMANIT`

<img src="https://user-images.githubusercontent.com/108768169/209649708-c4b8df8d-3166-40cd-87ea-6114666a5aa2.png"
 height="500px" width="500px"/>

🔴  results with `envvar_prefix=DMANIT`
<img src="https://user-images.githubusercontent.com/108768169/209649823-6bdd2878-1ec6-4abd-a10b-53f5d9ab8c71.png"
 height="500px" width="500px"/>


Thanks in advance.
Again, really thanks for maintaining and evolving this wonderful project!

Best regards.</div>

### Additional contract requirements

- `FlaskDynaconf(app, **kwargs)` accepts Dynaconf options as keyword arguments, and the option names may be written in any capitalisation.
- The supplied options are exposed on the Flask application's config as `envvar_prefix_for_dynaconf`, `env_switcher_for_dynaconf` and `environments_for_dynaconf`, and the `load_dotenv` option is exposed as `load_dotenv`.
- `DjangoDynaconf(settings_module_name, **kwargs)` accepts the abbreviated Dynaconf option names `envvar_prefix`, `env_switcher`, `environments` and `load_dotenv` as keyword arguments.
- The supplied options are exposed on the resulting settings object as `ENVVAR_PREFIX_FOR_DYNACONF`, `ENV_SWITCHER_FOR_DYNACONF` and `ENVIRONMENTS_FOR_DYNACONF`, and the `load_dotenv` option is exposed as `load_dotenv`.
