Unable to use chart.marginRight
Trying to use [chart.marginRight](https://api.highcharts.com/highcharts/chart.marginRight) but it results in an error:

```
  File "/home/ak/git/alphabuyer/.env/lib/python3.11/site-packages/highcharts_maps/chart.py", line 1006, in from_options
    options = validate_types(options, HighchartsOptions)
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/ak/git/alphabuyer/.env/lib/python3.11/site-packages/highcharts_core/decorators.py", line 102, in validate_types
    value = primary_type.from_dict(value)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/ak/git/alphabuyer/.env/lib/python3.11/site-packages/highcharts_core/metaclasses.py", line 370, in from_dict
    return cls(**kwargs)
           ^^^^^^^^^^^^^
  File "/home/ak/git/alphabuyer/.env/lib/python3.11/site-packages/highcharts_core/options/__init__.py", line 714, in __init__
    super().__init__(**kwargs)
  File "/home/ak/git/alphabuyer/.env/lib/python3.11/site-packages/highcharts_core/options/__init__.py", line 76, in __init__
    self.chart = kwargs.get('chart', None)
    ^^^^^^^^^^
  File "/home/ak/git/alphabuyer/.env/lib/python3.11/site-packages/highcharts_core/decorators.py", line 260, in func_wrapper
    value = validate_types(value,
            ^^^^^^^^^^^^^^^^^^^^^
  File "/home/ak/git/alphabuyer/.env/lib/python3.11/site-packages/highcharts_core/decorators.py", line 102, in validate_types
    value = primary_type.from_dict(value)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/ak/git/alphabuyer/.env/lib/python3.11/site-packages/highcharts_core/metaclasses.py", line 370, in from_dict
    return cls(**kwargs)
           ^^^^^^^^^^^^^
  File "/home/ak/git/alphabuyer/.env/lib/python3.11/site-packages/highcharts_core/options/chart/__init__.py", line 168, in __init__
    self.margin = kwargs.get('margin', None)
    ^^^^^^^^^^^
  File "/home/ak/git/alphabuyer/.env/lib/python3.11/site-packages/highcharts_core/options/chart/__init__.py", line 595, in margin
    self.margin_top = value[0]
    ^^^^^^^^^^^^^^^
  File "/home/ak/git/alphabuyer/.env/lib/python3.11/site-packages/highcharts_core/options/chart/__init__.py", line 683, in margin_top
    self._margin_top = validators.numeric(value, allow_empty = True)
                       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/ak/git/alphabuyer/.env/lib/python3.11/site-packages/validator_collection/_decorators.py", line 51, in func_wrapper
    return func(*args, **updated_kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/ak/git/alphabuyer/.env/lib/python3.11/site-packages/validator_collection/validators.py", line 1433, in numeric
    raise errors.CannotCoerceError(
validator_collection.errors.CannotCoerceError: value (null) cannot be coerced to a numeric form
```

I'm trying to use it in a stacked bar template file. Example:
```
{
    chart: {
        type: "bar",
        marginRight: 100,
        scrollablePlotArea: {
            minHeight: 1000,
            opacity: 1
        }
    },
    ...
}
```

P.S. chart.spacingRight doesn't work either.

### Additional contract requirements

- When parsing a JavaScript literal, `ChartOptions.from_js_literal()` must accept `marginRight: null` and expose the result as `margin_right is None`.
