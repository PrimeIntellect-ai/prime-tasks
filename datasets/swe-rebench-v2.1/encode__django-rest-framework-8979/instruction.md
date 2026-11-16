Invalid `self.instance` when validating the serializer using `many=True`
Currently it is almost impossible to use the same serializer with and without `many=True` and the problem that sometimes serializer depending on the instance state or value during serialization and validation (usually it is PATCH method and `partial=True`

This is the simplest example to understand:
```python
from django.db import models
from rest_framework import serializers


class MyClass(models.Model):
    name = models.CharField(max_length=100)
    status = models.CharField(max_length=100, blank=True)

    @property
    def is_valid(self):
        return self.name == 'valid'


class MyClassSerializer(serializers.ModelSerializer):
    class Meta:
        model = MyClass
        fields = ('id', 'name', 'status')

    def validate_status(self, value):
        if value and not self.instance.is_valid:
            raise serializers.ValidationError('Status cannot be set for invalid instance')
        return value


objs = MyClass.objects.bulk_create(
    objs=[
        MyClass(name='valid'),
        MyClass(name='invalid'),
        MyClass(name='other'),
    ]
)

serializer = MyClassSerializer(
    data=[{'status': 'set', 'id': instance.id} for instance in objs],
    instance=objs,
    many=True,
    partial=True,
)
serializer.is_valid()
print(serializer.errors)
```

Please note that it is just an example and real serializers and models can be much more complex. The case is working when we pass the single instance to the serializer but not working when we are trying to validate `bulk` operation, like update in bulk (let's say)

The following exception raised:
```
AttributeError: 'list' object has no attribute 'is_valid'
```

When expected behavior would be to get this one (pretty-printed):
```
[
    {},
    {'status': [ErrorDetail(string='Status cannot be set for invalid instance', code='invalid')]},
    {'status': [ErrorDetail(string='Status cannot be set for invalid instance', code='invalid')]},
]
```

P.S. I was able to manually patch the serializer to obtain the instance from the data provided, but I do not think that it should be done manually for every serializer. I assume that when we are validating the instance using PARTIAL, then the appropriate instance which is currently on validation, should be available inside the serializer. In this case we will be able to use the same serializer as single and multi entity-validation.

P.P.S. Also I think that if user require some logic for the list of objects, it should be placed inside the overridden `list_serializer_class`, no?
