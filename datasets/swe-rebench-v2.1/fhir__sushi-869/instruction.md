SUSHI does not recursively read input files
If the user has a folder structure like:
```
input
- fsh
    - fsh-file1.fsh
- resources
    - structuredefinitions
        - file1.json
    - codesystems
    - valuesets
```
Then SUSHI does not recursively read in `file1.json` as a predefined resource. This should probably be supported.
