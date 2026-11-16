Linter fails on CREATE INDEX when creating a new table
Here is an example `CreateModel` from Django:

```python
migrations.CreateModel(
    name='ShipmentMetadataAlert',
    fields=[
        ('deleted_at', models.DateTimeField(blank=True, db_index=True, null=True)),
        ('created_at', common.fields.CreatedField(default=django.utils.timezone.now, editable=False)),
        ('updated_at', common.fields.LastModifiedField(default=django.utils.timezone.now, editable=False)),
        ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False, verbose_name='ID')),
        ('message', models.TextField(blank=True, null=True)),
        ('level', models.CharField(blank=True, choices=[('HIGH', 'high'), ('MEDIUM', 'medium'), ('LOW', 'low')], max_length=16, null=True)),
        ('type', models.CharField(blank=True, choices=[('MOBILE_DEVICE_ALERT', 'MOBILE_DEVICE_ALERT'), ('NON_ACTIVE_CARRIER', 'NON_ACTIVE_CARRIER'), ('OTHER', 'OTHER')], max_length=32, null=True)),
        ('subtype', models.CharField(blank=True, choices=[('DRIVER_PERMISSIONS', 'DRIVER_PERMISSIONS'), ('DRIVER_LOCATION', 'DRIVER_LOCATION'), ('OTHER', 'OTHER')], max_length=32, null=True)),
        ('occurred_at', models.DateTimeField(null=True)),
        ('clear_alert_job_id', models.UUIDField(default=None, null=True)),
        ('metadata', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='alerts', to='shipments.ShipmentMetadata')),
    ],
    options={
        'abstract': False,
    }
)
```

Here are the SQL statements that this spits out in `sqlmigrate`:

```sql
BEGIN;
--
-- Create model ShipmentMetadataAlert
--
CREATE TABLE "shipments_shipmentmetadataalert" ("deleted_at" timestamp with time zone NULL, "created_at" timestamp with time zone NOT NULL, "updated_at" timestamp with time zone NOT NULL, "id" uuid NOT NULL PRIMARY KEY, "message" text NULL, "level" varchar(16) NULL, "type" varchar(32) NULL, "subtype" varchar(32) NULL, "occurred_at" timestamp with time zone NULL, "clear_alert_job_id" uuid NULL, "metadata_id" uuid NOT NULL);
ALTER TABLE "shipments_shipmentmetadataalert" ADD CONSTRAINT "shipments_shipmentme_metadata_id_f20850e8_fk_shipments" FOREIGN KEY ("metadata_id") REFERENCES "shipments_shipmentmetadata" ("id") DEFERRABLE INITIALLY DEFERRED;
CREATE INDEX "shipments_shipmentmetadataalert_deleted_at_c9a93342" ON "shipments_shipmentmetadataalert" ("deleted_at");
CREATE INDEX "shipments_shipmentmetadataalert_metadata_id_f20850e8" ON "shipments_shipmentmetadataalert" ("metadata_id");
COMMIT;
```

This is an error from the linter as it outputs the error `CREATE INDEX locks table`. But the table is being created within the migration, it just needs to recognize that.

It seems like the `CREATE INDEX` detection should work the same way that the `ADD_UNIQUE` detection works where it detects that the create table is happening in the same migration:

https://github.com/3YOURMIND/django-migration-linter/blob/db71a9db23746f64d41d681f3fecb9b066c87338/django_migration_linter/sql_analyser/base.py#L26-L40
