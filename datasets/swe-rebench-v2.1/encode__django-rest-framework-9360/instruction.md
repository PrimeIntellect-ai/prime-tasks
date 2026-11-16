3.15 regression: Serializer validation failed for unique together constraint
The new 3.15.0 release introduced a bug with validation unique constraint.

Code to reproduce an error:
```
from django.db import models
from rest_framework import serializers

class Pet(models.Model):
    name = models.CharField(max_length=100)
    animal_type = models.CharField(max_length=100)
    can_fly = models.BooleanField(null=True)

    class Meta:
        constraints = (
            UniqueConstraint(
                fields=["name", "animal_type"],
                name="unique_pet",
                condition=Q(can_fly__isnull=True),
            ),
        )


class PetSerializer(serializers.ModelSerializer):
    class Meta:
        model = Pet
        fields = ('name', 'animal_type', 'can_fly')


Pet.objects.create(animal_type='dog', name='Fluffy', can_fly=None)
serializer = PetSerializer(data={
    'can_fly': False,
    'animal_type': 'dog',
    'name': 'Fluffy'
})
serializer.is_valid(raise_exception=True)
```

The last line raises the error:
```
Error
Traceback (most recent call last):
    rest_framework.exceptions.ValidationError: {
        'non_field_errors': [ErrorDetail(string='The fields name, animal_type must make a unique set.', code='unique')]
    }
```

Validation ignores that `can_fly` field is present in the `serializer.initial_data` and just runs `UniqueTogetherValidator` for `animal_type` and `name` fields.
