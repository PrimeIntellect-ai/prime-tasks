Consider --warn option when dealing with duplicate metadata and invalid requirement string warnings
### What pipdeptree version are you using?

2.18.1

### Are you running pipdeptree in a virtual environment?

- [ ] Yes

### Describe the problem

The new duplicate metadata warning text and invalid requirement string warning text (which I both added) do not account for the --warn option. An example:
```console
vscode ➜ /workspaces/pipdeptree (main) $ pipdeptree --warn silence
Warning!!! Duplicate package metadata found:
"/usr/local/lib/python3.8/site-packages"
  pip                              23.0.1           (using 24.0, "/home/vscode/.local/lib/python3.8/site-packages")
------------------------------------------------------------------------
covdefaults==2.3.0
└── coverage [required: >=6.0.2, installed: 7.4.4]
. . .
```

### Additional contract requirements

When `--warn silence` is selected, duplicate-package-metadata warnings and invalid-requirement warnings must not be printed.
