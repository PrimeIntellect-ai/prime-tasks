Django 5.2 compatibility
### `display_for_field` changes
In [a9c79b4](https://github.com/django/django/commit/a9c79b462923ce366101db1b5a3fff3d1dad870c), a new keyword argument was added to `display_for_field`.

This needs to be updated in the monkey-patching done in `djmoney/admin.py`, https://github.com/django-money/django-money/blob/835c1ab867d11137b964b94936692bea67a038ec/djmoney/admin.py#L14-L17

### Removal of `django.core.serializers.python._get_model`
In [ee5147c](https://github.com/django/django/commit/ee5147cfd7de2add74a285537a8968ec074e70cd), the deserializer was refactored into a class.

The [docs on Custom serialization formats](https://docs.djangoproject.com/en/5.2/topics/serialization/#custom-serialization-formats) suggests using a class

### Additional contract requirements

- The new keyword argument added to `display_for_field` is named `avoid_link`. The monkey-patch must accept it and honour it when displaying non-money fields.
- On Django 5.2 and later, deserialization must use Django’s model-resolution mechanism for each `"app_label.model_name"` identifier. Customized model resolution must determine which model is deserialized, and an identifier Django cannot resolve must raise `DeserializationError`.
