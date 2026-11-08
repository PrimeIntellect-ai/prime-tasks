Configuration: language version support
<!-- ⚠️ If you do not respect this template, your issue will be closed -->
<!-- ⚠️ Make sure to browse the opened and closed issues to confirm this idea does not exist. -->

### What is the expected behavior?
Add language support for configuration

For example: for Python it would be 3.6, 3.7 etc


```json
{
     "language": {
           "name": "python",
           "versions": ["3.6", "3.7"]
     }
}
```

### Additional contract requirements

- Add a public class `PythonLanguageConfiguration` in module `ecosystem.models.configuration` representing the Python language. Its `name` is `"python"`. It accepts an optional list of `versions`; when none are supplied, `versions` defaults to `["3.6", "3.7", "3.8", "3.9"]`. It provides a class method `default_version()` that returns that default list.
- `RepositoryConfiguration` and `PythonRepositoryConfiguration` accept an optional `language` argument holding a language configuration; when it is omitted, a Python language configuration is used. The stored `language` exposes `name` and `versions`. Omitted list arguments (`dependencies_files`, `extra_dependencies`, `tests_command`, `styles_check_command`, `coverages_check_command`) default to empty lists.
- When a configuration is loaded from a JSON file whose `language` object contains `name` and `versions`, the loaded configuration's `language` reflects those values. When the JSON has no `language` entry, the loaded configuration's `language` is a Python language configuration with the default versions.
