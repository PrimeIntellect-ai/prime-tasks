TypeVar broke with 1.25
 @hoodmane for some reason #397  broke tox documentation on TypeVar

<img width="416" alt="image" src="https://github.com/tox-dev/sphinx-autodoc-typehints/assets/690238/1e77d6a8-1825-4162-bc73-be835adad963">

https://github.com/tox-dev/tox/actions/runs/6822355429/job/18554265718

Any idea why is that?

_Originally posted by @gaborbernat in https://github.com/tox-dev/sphinx-autodoc-typehints/issues/397#issuecomment-1806076131_

### Additional contract requirements

TypeVar annotations must render correctly in Sphinx-generated documentation when used as function parameter and return annotations, and when nested inside parameterized annotations. The TypeVar name must remain visible. If the output displays a TypeVar reference followed by parenthesized details, keep the reference separate from those details so it remains independently parseable; a rendering that displays the TypeVar name alone is also acceptable.
