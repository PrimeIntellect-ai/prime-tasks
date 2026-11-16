[BUG] grayskull 1.6.0 fails to add minimum "safe" python on noarch packages
The `humre` is a norach package but fails to specify a minimum python requirement. In the past grayskull, with the `--strict-conda-forge`, used to add the `>=3.6` automatically but that is no longer true:

```
grayskull pypi --strict-conda-forge humre
```

### Additional contract requirements

- `grayskull.__main__.create_python_recipe(pkg_name, is_strict_cf=False, version=None, **kwargs)` returns a `(recipe, metadata)` tuple, where `recipe` is a dictionary representing the generated conda recipe.
- For `create_python_recipe("humre", is_strict_cf=True, version="0.1.1")`, `recipe["requirements"]["run"]` must be exactly `["python >=3.6"]`.
- Running the CLI command `grayskull pypi --strict-conda-forge humre` must generate a recipe whose `requirements.run` includes `python >=3.6`.
