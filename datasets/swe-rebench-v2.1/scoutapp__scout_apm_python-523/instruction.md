Error with the scout add-on in Heroku
With version 2.14.1 of this package, I encounter the following error:
`  File "/code/nluproxy/__init__.py", line 3, in <module>

    from .celery import app as celery_app

  File "/code/nluproxy/celery.py", line 12, in <module>

    scout_apm.celery.install(app)

  File "/usr/local/lib/python3.7/site-packages/scout_apm/celery.py", line 58, in install

    installed = scout_apm.core.install()

  File "/usr/local/lib/python3.7/site-packages/scout_apm/compat.py", line 132, in wrapper

    return func(*args, **kwargs)

  File "/usr/local/lib/python3.7/site-packages/scout_apm/core/__init__.py", line 46, in install

    report_app_metadata()

  File "/usr/local/lib/python3.7/site-packages/scout_apm/core/metadata.py", line 17, in report_app_metadata

    event_value=get_metadata(),

  File "/usr/local/lib/python3.7/site-packages/scout_apm/core/metadata.py", line 37, in get_metadata

    "libraries": get_python_packages_versions(),

  File "/usr/local/lib/python3.7/site-packages/scout_apm/core/metadata.py", line 60, in get_python_packages_versions

    for distribution in distributions()

TypeError: '<' not supported between instances of 'NoneType' and 'str'

`
