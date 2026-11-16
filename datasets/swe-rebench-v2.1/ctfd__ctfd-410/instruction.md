Move plugin focused functions to the plugins folder
`override_template`
`register_plugin_script`
`register_plugin_stylesheet`

These should move to the plugins directory.

### Additional contract requirements

- `override_template`, `register_plugin_script`, and `register_plugin_stylesheet` are importable from the `CTFd.plugins` module.
- `override_template(template_path, html_content)` replaces the template identified by `template_path` with `html_content` and returns `None`. Admin-panel templates are identified by paths that begin with `admin/` (for example `admin/team.html`).
- `register_plugin_script(script_path)` adds `script_path` to the scripts rendered on every page and returns `None`.
- `register_plugin_stylesheet(stylesheet_path)` adds `stylesheet_path` to the stylesheets rendered on every page and returns `None`.
