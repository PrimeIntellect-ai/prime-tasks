Linter failing when using django 'through'
### through doc
https://docs.djangoproject.com/en/4.0/ref/models/fields/#django.db.models.ManyToManyField.through

### Example code
```
def forwards_func(apps, schema_editor):
    Question = apps.get_model("solution", "Question")
    ...
    Question.many_to_may.through.objects.bulk_create(...)                 <- this line?
    ...
```
### Example Error
```
(fs_solution, 0002_my_migration)... ERR (cached)
        'forwards_func': Could not find an 'apps.get_model("...", "through")' call. Importing the model directly is incorrect for data migrations.
```
