[BUG] "Using .* with relational operator is superfluous and deprecated"
Consider the package [`dbt-core`](https://pypi.org/project/dbt-core/#files). The `install_requires` contains

```python
        "dbt-extractor~=0.4.1",
```

[Running Grayskull](https://marcelotrevisani.info:8000/recipe/?name=dbt-core&version=1.1.1) this gets translated into

```yaml
    - dbt-extractor >=0.4.1,==0.4.*
```

Then running boa with `conda mambabuild -c conda-forge .` or `conda build -c conda-forge .` produces the warning

```
WARNING:conda.models.version:Using .* with relational operator is superfluous and deprecated and will be removed in a future version of conda. Your spec was 0.4.*, but conda is ignoring the .* and treating it as 0.4
```

This results in the unsatisfiable dependency `>=0.4.1,==0.4` since `==0.4` seems to imply 0.4.0 and excludes 0.4.1.

Interestingly, if I change it to a single equals (`>=0.4.1,=0.4.*`) then it doesn't complain and seems to work as intended.

### Additional contract requirements

- Preserve compatible-release constraints with the `~=` operator: `ensure_pep440("pytest ~=5.3.2")` must return `"pytest ~=5.3.2"`, normalized requirements must retain `"pytest ~=5.3.2"`, and the generated run requirement for `kedro=0.17.6` must include `"anyconfig ~=0.10.0"`.
