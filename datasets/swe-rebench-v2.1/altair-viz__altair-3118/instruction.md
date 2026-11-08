Code path in utils emits `jsonschema` deprecation warning
[jsonschema](https://pypi.org/project/jsonschema/) recently released a new version and introduced a new deprecation warning around `jsonschema.RefResolver` - this is utilized in `altair/utils/schemapi.py`.

You can replicate with the following code:
```python
import altair as alt

alt.StandardType("...")
```

```
/opt/hostedtoolcache/Python/3.8.17/x64/lib/python3.8/site-packages/altair/vegalite/v4/schema/core.py:15771: in __init__
    super(StandardType, self).__init__(*args)
/opt/hostedtoolcache/Python/3.8.17/x64/lib/python3.8/site-packages/altair/utils/schemapi.py:197: in __init__
    self.to_dict(validate=True)
/opt/hostedtoolcache/Python/3.8.17/x64/lib/python3.8/site-packages/altair/utils/schemapi.py:358: in to_dict
    self.validate(result)
/opt/hostedtoolcache/Python/3.8.17/x64/lib/python3.8/site-packages/altair/utils/schemapi.py:462: in validate
    resolver = jsonschema.RefResolver.from_schema(cls._rootschema or cls._schema)
/opt/hostedtoolcache/Python/3.8.17/x64/lib/python3.8/site-packages/jsonschema/__init__.py:42: in __getattr__
    warnings.warn(
E   DeprecationWarning: jsonschema.RefResolver is deprecated as of v4.18.0, in favor of the https://github.com/python-jsonschema/referencing library, which provides more compliant referencing behavior as well as more flexible APIs for customization. A future release will remove RefResolver. Please file a feature request (on referencing) if you are missing an API for the kind of customization you need.
```

---

Please follow these steps to make it more efficient to solve your issue:

- [x] Since Altair is a Python wrapper around the Vega-Lite visualization grammar, [most bugs should be reported directly to Vega-Lite](https://github.com/vega/vega-lite/issues). You can click the Action Button of your Altair chart and "Open in Vega Editor" to create a reproducible Vega-Lite example and see if you get the same error in the Vega Editor.
- [x] Search for duplicate issues.
- [x] Use the latest version of Altair.
- [x] Describe how to reproduce the bug and include the full code and data to reproduce it, ideally using a sample data set from `vega_datasets`.
