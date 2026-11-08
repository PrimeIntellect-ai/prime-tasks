[Enhancement] Avoid expansion of whitespace when using many MCMs in MPL drawer
![Image](https://github.com/user-attachments/assets/9c3ccfc2-c3bd-4fcc-9d52-91242cb90d83)
When using many MCM operations, the MPL drawer fails to recycle whitespace. This makes readability a challenge when MCMs grow to large numbers.

The enhancement request is to:
* Reuse available whitespace for the classical lines from MCMs
* Ensure area is between by MCM counts and where they are used.

### Additional contract requirements

- The text drawer (`qml.draw`) must also reuse classical-wire lines for non-overlapping MCM usages. In the affected multi-measurement drawings, the classical-line rows are:

```
                ╚══════════║═══╬══║═══║══════╝     ║      ╚════╩═════════╣
                           ╚═══╩══╩═══║════════════╬═════════════════════╝
                                      ╚════════════╝
```

For the split-lines drawing, they are:

```
    ╚════╩═════════╣
═══════════════════╝

```
