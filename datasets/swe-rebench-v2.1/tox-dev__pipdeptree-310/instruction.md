Slightly different output for --json-tree and --json
--json-tree says `required_version": "Any"`

but

--json says  `"required_version": null`


This command

```bash
pipdeptree  --json-tree -p wxPython
```

produces this output

```json
   {
        "key": "wxpython",
        "package_name": "wxPython",
        "installed_version": "4.2.1",
        "required_version": "4.2.1",
        "dependencies": [
            {
                "key": "numpy",
                "package_name": "numpy",
                "installed_version": "1.26.2",
                "required_version": "Any",
                "dependencies": []
            },
            {
                "key": "pillow",
                "package_name": "Pillow",
                "installed_version": "10.1.0",
                "required_version": "Any",
                "dependencies": []
            },
            {
                "key": "six",
                "package_name": "six",
                "installed_version": "1.16.0",
                "required_version": "Any",
                "dependencies": []
            }
        ]
    }
]
```

but this command

```bash
pipdeptree  --json -p wxPython
```


produces this output

```json
[
    {
        "package": {
            "key": "numpy",
            "package_name": "numpy",
            "installed_version": "1.26.2"
        },
        "dependencies": []
    },
    {
        "package": {
            "key": "pillow",
            "package_name": "Pillow",
            "installed_version": "10.1.0"
        },
        "dependencies": []
    },
    {
        "package": {
            "key": "six",
            "package_name": "six",
            "installed_version": "1.16.0"
        },
        "dependencies": []
    },
    {
        "package": {
            "key": "wxpython",
            "package_name": "wxPython",
            "installed_version": "4.2.1"
        },
        "dependencies": [
            {
                "key": "numpy",
                "package_name": "numpy",
                "installed_version": "1.26.2",
                "required_version": null
            },
            {
                "key": "pillow",
                "package_name": "Pillow",
                "installed_version": "10.1.0",
                "required_version": null
            },
            {
                "key": "six",
                "package_name": "six",
                "installed_version": "1.16.0",
                "required_version": null
            }
        ]
    }
]
```

### Additional contract requirements

For a dependency with no version specifier, `--json` and `--json-tree` must report the same `required_version` value. Use `"Any"` as that value.
