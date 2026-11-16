Add searchpath to TemplateNotFound exception message
This was from https://github.com/apache/airflow/issues/23333 where trying to load a template that doesn't exist in the searchpath raises `TemplateNotFound` exception. In this case an absolute path is used which causes issue over concatenation but including `searchpath` might be a useful addition so that user can know under the paths under which the template was searched for and will be helpful during debugging.

https://github.com/pallets/jinja/blob/6f79daafe868b8ef20baecdcb45d12299529ed2e/src/jinja2/loaders.py#L218

Current exception :

```
jinja2.exceptions.TemplateNotFound: /tmp/a/python_template_exts.txt
```

Proposed exception to include searchpath :

```
jinja2.exceptions.TemplateNotFound: /tmp/a/python_template_exts.txt not found in search path ['/opt/airflow/tests/operators', '/']
```

### Additional contract requirements

- For a `FileSystemLoader` failure, the message must begin with `'{name}' not found in search path: ` when one search path is configured, or `'{name}' not found in search paths: ` when multiple search paths are configured, where `{name}` is the template name represented with quotes (for example, `'missing' not found in search path: `).
- When a configured search path is the string `other` and follows another path, the message must contain `, 'other'`.
