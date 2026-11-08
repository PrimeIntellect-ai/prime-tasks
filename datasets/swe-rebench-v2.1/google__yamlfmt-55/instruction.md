Basic formatter spuriously deletes backslashes in strings after glob run
When running yamlfmt basic formatting with a config file and targeting several paths in a repository, the formatter spuriously deletes backslashes and thereby breaks the semantics of those YAML files. For example

```yaml
outer:
    - inner: "python3 -m some.module \\${VARIABLE_:-}"
```

becomes

```yaml
outer:
    - inner: "python3 -m some.module ${VARIABLE_:-}"
```

and

```yaml
outer:
  - name: something
    regex: '\(\d+, "Unknown database .*'
```

becomes

```yaml
outer:
  - name: something
    regex: '(d+, "Unknown database .*'
```

which are not semantically identical. Strangely enough, targeting these individual files with the formatter doesn't change them this way. Only running the formatter over a glob of YAML paths in my directory has this effect.

Unfortunately, I can't attach the entire directory as it's proprietary. But I'm hoping you have some insights as to why this might happen. I'll try to create a sanitized reproduction if possible.
