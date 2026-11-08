Node.__hash__ raises exception on all parsed input
I've looked into a regression in https://github.com/pallets/jinja/commit/60293416db69782fd048a7820667afa4ae7c423b where the `Node.__hash__` method was changed [HIDDEN]

Since the fields contain lists, the resulting tuple is not hashable.

Test case:
```python
class TestHashing:
    def test_template_hash(self, env):
        template = env.parse("hash test")
        assert hash(template)
```
Output:
```python
self = Template(body=[Output(nodes=[TemplateData(data='hash test')])])

    def __hash__(self):
>       [HIDDEN]
E       TypeError: unhashable type: 'list'
```

This behaviour breaks some third party packages such as `django-compressor`. See https://github.com/django-compressor/django-compressor/issues/1060

Environment:

- Python version: 3.10
- Jinja version: 3.0.x

### Additional contract requirements

- Calling `hash()` on a parsed template must complete without raising an exception caused by its list-valued fields.
- Node hashing must be based on node identity, not on node field values.
