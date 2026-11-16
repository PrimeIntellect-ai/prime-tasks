Base classes may only be used by one derived class
If I create a base class with some common fields I can create a subclass and it works, but if I create more than one subclass from the same base class the validation fails.

I added `tests/test_inheritance.py`
```
from dataclasses import dataclass
from dataclasses_jsonschema import JsonSchemaMixin


def test_inheritance():
    @dataclass
    class Base(JsonSchemaMixin):
        base: str

    @dataclass
    class Derived1(Base):
        derived1: str

    @dataclass
    class Derived2(Base):
        derived2: str

    data1 = {"derived1": "d", "base": "b"}
    d = Derived1.from_dict(data1)
    assert d.to_dict() == data1

    data2 = {"derived2": "d", "base": "b"}
    d = Derived2.from_dict(data2)
    assert d.to_dict() == data2
```
Expected output: the test should pass.
Actual output:
```
GLOB sdist-make: /Users/duncan.booth/github/dataclasses-jsonschema/setup.py
py37 inst-nodeps: /Users/duncan.booth/github/dataclasses-jsonschema/.tox/.tmp/package/1/dataclasses-jsonschema-2.6.2.dev0+ge79e8e1.d20190712.zip
py37 installed: apispec==2.0.2,apispec-webframeworks==0.4.0,atomicwrites==1.3.0,attrs==19.1.0,Click==7.0,dataclasses-jsonschema==2.6.2.dev0+ge79e8e1.d20190712,entrypoints==0.3,flake8==3.7.8,Flask==1.1.1,importlib-metadata==0.18,itsdangerous==1.1.0,Jinja2==2.10.1,jsonschema==3.0.1,MarkupSafe==1.1.1,mccabe==0.6.1,more-itertools==7.1.0,mypy==0.711,mypy-extensions==0.4.1,packaging==19.0,pluggy==0.12.0,py==1.8.0,pycodestyle==2.5.0,pyflakes==2.1.1,pyparsing==2.4.0,pyrsistent==0.15.3,pytest==5.0.1,pytest-ordering==0.6,python-dateutil==2.8.0,PyYAML==5.1.1,six==1.12.0,typed-ast==1.4.0,typing-extensions==3.7.4,wcwidth==0.1.7,Werkzeug==0.15.4,zipp==0.5.2
py37 run-test-pre: PYTHONHASHSEED='2578755219'
py37 run-test: commands[0] | pytest tests
==================================================================== test session starts =====================================================================
platform darwin -- Python 3.7.2, pytest-5.0.1, py-1.8.0, pluggy-0.12.0
cachedir: .tox/py37/.pytest_cache
rootdir: /Users/duncan.booth/github/dataclasses-jsonschema
plugins: ordering-0.6
collected 28 items

tests/test_core.py ..........................                                                                                                          [ 92%]
tests/test_inheritance.py F                                                                                                                            [ 96%]
tests/test_apispec_plugin.py .                                                                                                                         [100%]

========================================================================== FAILURES ==========================================================================
______________________________________________________________________ test_inheritance ______________________________________________________________________

self = <jsonschema.validators.RefResolver object at 0x107a187b8>
document = {'$schema': 'http://json-schema.org/draft-06/schema#', 'allOf': [{'$ref': '#/definitions/Base'}, {'properties': {'deri...{'type': 'string'}}, 'required': ['derived1'], 'type': 'object'}], 'description': 'Derived1(base: str, derived1: str)'}
fragment = 'definitions/Base'

    def resolve_fragment(self, document, fragment):
        """
        Resolve a ``fragment`` within the referenced ``document``.

        Arguments:

            document:

                The referent document

            fragment (str):

                a URI fragment to resolve within it
        """

        fragment = fragment.lstrip(u"/")
        parts = unquote(fragment).split(u"/") if fragment else []

        for part in parts:
            part = part.replace(u"~1", u"/").replace(u"~0", u"~")

            if isinstance(document, Sequence):
                # Array indexes should be turned into integers
                try:
                    part = int(part)
                except ValueError:
                    pass
            try:
>               document = document[part]
E               KeyError: 'definitions'

.tox/py37/lib/python3.7/site-packages/jsonschema/validators.py:776: KeyError

During handling of the above exception, another exception occurred:

    def test_inheritance():
        @dataclass
        class Base(JsonSchemaMixin):
            base: str

        @dataclass
        class Derived1(Base):
            derived1: str

        @dataclass
        class Derived2(Base):
            derived2: str

        data1 = {"derived1": "d", "base": "b"}
        d = Derived1.from_dict(data1)
        assert d.to_dict() == data1

        data2 = {"derived2": "d", "base": "b"}
>       d = Derived2.from_dict(data2)

tests/test_inheritance.py:24:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
dataclasses_jsonschema/__init__.py:396: in from_dict
    cls._validate(data)
dataclasses_jsonschema/__init__.py:383: in _validate
    validate_func(data, cls.json_schema())
.tox/py37/lib/python3.7/site-packages/jsonschema/validators.py:897: in validate
    error = exceptions.best_match(validator.iter_errors(instance))
.tox/py37/lib/python3.7/site-packages/jsonschema/exceptions.py:293: in best_match
    best = next(errors, None)
.tox/py37/lib/python3.7/site-packages/jsonschema/validators.py:323: in iter_errors
    for error in errors:
.tox/py37/lib/python3.7/site-packages/jsonschema/_validators.py:303: in allOf
    for error in validator.descend(instance, subschema, schema_path=index):
.tox/py37/lib/python3.7/site-packages/jsonschema/validators.py:339: in descend
    for error in self.iter_errors(instance, schema):
.tox/py37/lib/python3.7/site-packages/jsonschema/validators.py:323: in iter_errors
    for error in errors:
.tox/py37/lib/python3.7/site-packages/jsonschema/_validators.py:247: in ref
    scope, resolved = validator.resolver.resolve(ref)
.tox/py37/lib/python3.7/site-packages/jsonschema/validators.py:734: in resolve
    return url, self._remote_cache(url)
.tox/py37/lib/python3.7/site-packages/jsonschema/validators.py:746: in resolve_from_url
    return self.resolve_fragment(document, fragment)
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

self = <jsonschema.validators.RefResolver object at 0x107a187b8>
document = {'$schema': 'http://json-schema.org/draft-06/schema#', 'allOf': [{'$ref': '#/definitions/Base'}, {'properties': {'deri...{'type': 'string'}}, 'required': ['derived1'], 'type': 'object'}], 'description': 'Derived1(base: str, derived1: str)'}
fragment = 'definitions/Base'

    def resolve_fragment(self, document, fragment):
        """
        Resolve a ``fragment`` within the referenced ``document``.

        Arguments:

            document:

                The referent document

            fragment (str):

                a URI fragment to resolve within it
        """

        fragment = fragment.lstrip(u"/")
        parts = unquote(fragment).split(u"/") if fragment else []

        for part in parts:
            part = part.replace(u"~1", u"/").replace(u"~0", u"~")

            if isinstance(document, Sequence):
                # Array indexes should be turned into integers
                try:
                    part = int(part)
                except ValueError:
                    pass
            try:
                document = document[part]
            except (TypeError, LookupError):
                raise exceptions.RefResolutionError(
>                   "Unresolvable JSON pointer: %r" % fragment
                )
E               jsonschema.exceptions.RefResolutionError: Unresolvable JSON pointer: 'definitions/Base'

.tox/py37/lib/python3.7/site-packages/jsonschema/validators.py:779: RefResolutionError
====================================================================== warnings summary ======================================================================
.tox/py37/lib/python3.7/site-packages/jinja2/utils.py:485
  /Users/duncan.booth/github/dataclasses-jsonschema/.tox/py37/lib/python3.7/site-packages/jinja2/utils.py:485: DeprecationWarning: Using or importing the ABCs from 'collections' instead of from 'collections.abc' is deprecated, and in 3.8 it will stop working
    from collections import MutableMapping

.tox/py37/lib/python3.7/site-packages/jinja2/runtime.py:318
  /Users/duncan.booth/github/dataclasses-jsonschema/.tox/py37/lib/python3.7/site-packages/jinja2/runtime.py:318: DeprecationWarning: Using or importing the ABCs from 'collections' instead of from 'collections.abc' is deprecated, and in 3.8 it will stop working
    from collections import Mapping

.tox/py37/lib/python3.7/site-packages/_pytest/mark/structures.py:332
  /Users/duncan.booth/github/dataclasses-jsonschema/.tox/py37/lib/python3.7/site-packages/_pytest/mark/structures.py:332: PytestUnknownMarkWarning: Unknown pytest.mark.last - is this a typo?  You can register custom marks to avoid this warning - for details, see https://docs.pytest.org/en/latest/mark.html
    PytestUnknownMarkWarning,

-- Docs: https://docs.pytest.org/en/latest/warnings.html
====================================================== 1 failed, 27 passed, 3 warnings in 0.42 seconds =======================================================
ERROR: InvocationError for command /Users/duncan.booth/github/dataclasses-jsonschema/.tox/py37/bin/pytest tests (exited with code 1)
__________________________________________________________________________ summary ___________________________________________________________________________
ERROR:   py37: commands failed
```

The code fails when attempting to do `Derived2.from_dict(...)` but only if we have previously called `Derived1.from_dict(...)`. Whichever order I try to validate the data the first one succeeds and the second one fails.

[HIDDEN] If I change the code so that `Base` no longer inherits from `JsonSchemaMixin` the two derived classes no longer share the mixin's attributes and everything works.

### Additional contract requirements

- For sibling dataclass subclasses of a common base that inherits from JsonSchemaMixin, each subclass must be usable with `from_dict` to deserialize its own valid data, and `to_dict` must preserve that data, regardless of which sibling is used first.
