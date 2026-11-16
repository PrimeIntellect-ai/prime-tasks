s-a-t breaks default_role in parameter descriptions
When using sphinx-autodoc-typehints, text between single backticks in parameter descriptions gets rendered as `<cite/>` nodes, i.e. using docutils’ default [`title-reference`](https://docutils.sourceforge.io/docs/ref/rst/roles.html#title-reference) role instead of the role we configured.

I don’t know exactly why, but removing s-a-t from the plugin list fixes this, and you’re e.g. using a [HIDDEN] in several places which has that behavior. [HIDDEN]

https://github.com/tox-dev/sphinx-autodoc-typehints/blob/0bec1bc2def5c56150fbeccf655d3fdf93c7bf12/src/sphinx_autodoc_typehints/__init__.py#L799

https://github.com/tox-dev/sphinx-autodoc-typehints/blob/0bec1bc2def5c56150fbeccf655d3fdf93c7bf12/src/sphinx_autodoc_typehints/attributes_patch.py#L66

[HIDDEN]
