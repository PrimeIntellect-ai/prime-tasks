Adding an index with a NOT NULL condition incorrectly triggers NOT_NULL rule
Adding an index with a `WHERE` clause including `NOT NULL` gets flagged as a `NOT NULL constraint on columns` error.

## Steps to reproduce

The follow migration operation:

```python
AddIndexConcurrently(
    model_name="prediction",
    index=models.Index(
        condition=models.Q(
            ("data_deleted_at__isnull", True),
            ("delete_data_after__isnull", False),
        ),
        fields=["delete_data_after"],
        name="delete_data_after_idx",
    ),
),
```

Generates the following SQL:

```sql
CREATE INDEX CONCURRENTLY "delete_data_after_idx" ON "models_prediction" ("delete_data_after") WHERE ("data_deleted_at" IS NULL AND "delete_data_after" IS NOT NULL);
```

When linted this is flagged as an error because of the `NOT NULL`, when it ought to be a safe operation.

## Investigation

[HIDDEN]

https://github.com/3YOURMIND/django-migration-linter/blob/202a6d9d5dea83528cb52fd7481a5a0565cc6f83/django_migration_linter/sql_analyser/base.py#L43
