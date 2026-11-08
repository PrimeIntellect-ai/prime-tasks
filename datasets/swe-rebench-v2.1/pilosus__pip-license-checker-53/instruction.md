Show all licenses if more than one classifier specified
See [cchardet](https://pypi.org/project/cchardet/). It has more than one specific license in the trove classifiers. PyPI website shows all of them, ignoring single one in `license` field

### Additional contract requirements

- When multiple specific license classifiers are present, return their license names in classifier order, joined by `, `; for the tested classifiers, the exact result is `GNU General Public License (GPL), GNU Library or Lesser General Public License (LGPL), Mozilla Public License 1.1 (MPL 1.1)`.
