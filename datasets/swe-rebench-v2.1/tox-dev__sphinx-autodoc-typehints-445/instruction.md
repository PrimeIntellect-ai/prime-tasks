Sphinx option rst_prolog and rst_epilog break return type injection
When adding any of those sphinx options: [rst_epilog](https://www.sphinx-doc.org/en/master/usage/configuration.html#confval-rst_epilog) or [rst_prolog](https://www.sphinx-doc.org/en/master/usage/configuration.html#confval-rst_prolog)

It will break the return type injection. For example we have one for the minimum python version (`min_python_version`).

When using the `rst_epilog` all of the return types become the version:
![image](https://github.com/tox-dev/sphinx-autodoc-typehints/assets/17804711/2019e67b-4e22-4694-83a4-9d5726268034)

If you use the `rst_prolog` the return types are working again, but now the return type always appear at the top of the class, before the header and parameters.

![image](https://github.com/tox-dev/sphinx-autodoc-typehints/assets/17804711/593b1c23-2f74-41c8-abe1-8fc82d4f4206)

Disabling either will produce the correct result:
![image](https://github.com/tox-dev/sphinx-autodoc-typehints/assets/17804711/0e0ea99d-a67d-4100-85c9-9e251757a301)

Due to the rst, it creates a bunch of nodes either before or after: `<substitution_definition names="min_python_version">3.8</substitution_definition>` which mess with the line parsing.  Since it's assuming certain things come after paramters, it doesn't pick the correct lines.
