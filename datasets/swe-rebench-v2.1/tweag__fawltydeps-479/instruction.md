Support wildcards in `ignore-unused`.
**Is your feature request related to a problem? Please describe.**

I have a codebase with types stubs and pytest plugins as dev dependencies. When running `fawltydeps` they all appear as false positives (they're not `import`ed directly in our codebase but they're providing pytest fixtures and typing support).

Now, I know I can individually `ignore-unused` in the configuration, but there are a lot of them. So I end up maintaining a rather long list of package names for this tool to ignore (list of `pytest-x` and `types-y`) in addition to the _actual_ dependencies.

**Describe the solution you'd like**

I'm not sure if there's a better way, but something that comes to mind would be to support wildcards:
```yaml
[tool.fawltydeps]
ignore_unused = ["pytest-*", "types-*]
```

```sh
fawltydeps . --ignore-unused="pytest-*" --ignore-unused="types-*"
```

**Describe alternatives you've considered**

This _could maybe_ be automatically handled in the logic of the code, something like how you [handle the `"-stubs"` suffix](https://github.com/tweag/FawltyDeps/blob/499f137177937a06fac11ce6f9b6eb78a422aae3/fawltydeps/packages.py#L87). But I'm not sure that's better.

**Additional context**
