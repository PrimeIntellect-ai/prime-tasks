Migrator::create() adds Fields from Join to Model table
Some Code from my application (Tour Model):
```php
        $ttJoin = $this->leftJoin('tour_type', ['masterField' => 'tour_type_id']);

        $ttJoin->addField('activity_id', ['system' => true]);
```
When using `Migrator::create()` to create a table for this Model, the field `activity_id` is added.

I will provide a minimal test to reproduce.
