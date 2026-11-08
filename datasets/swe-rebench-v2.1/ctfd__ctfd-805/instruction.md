Create admin panel only scripts + stylesheet plugin interfaces
```
def register_script(url):
    SCRIPTS.append(url)


def register_stylesheet(url):
    STYLESHEETS.append(url)


def get_registered_scripts():
    return SCRIPTS


def get_registered_stylesheets():
    return STYLESHEETS
```

The above code exists for themes but the admin panel doesn't make use of it and it really shouldn't. We should make functions to add things specifically to the admin panel.

### Additional contract requirements

Plugin authors can use `register_admin_plugin_script(url)` to register a script for the admin panel, and `register_admin_plugin_stylesheet(url)` to register a stylesheet for the admin panel. These registrations are separate from ordinary theme script and stylesheet registrations: the assets are included on admin pages and are not included on ordinary theme pages.
