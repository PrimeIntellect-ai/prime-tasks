UUID column generates a reference when `use_constraints` config option is enabled
<!-- PLEASE COMPLETE THIS TEMPLATE -->

* Laravel Version: 8.22.1
* PHP Version: 8.0
* Blueprint Version: 1.20.2
* Platform: Mac

### Issue:
If I name a UUID column to 'uuid' Blueprint generates a foreign key to a table that doesn't exist.


### draft.yaml:
```yaml
models:
  Vat:
    uuid: uuid
```

Expected outcome
```php
        Schema::create('vats', function (Blueprint $table) {
            $table->id();
            $table->uuid('uuid');
            $table->timestamps();
        });
```

Blueprint generates a foreign key to a table that doesn't exist:
```php
        Schema::create('vats', function (Blueprint $table) {
            $table->id();
            $table->uuid('uuid');
            $table->foreign('uuid')->references('uuid')->on('uuids')->onDelete('cascade');
            $table->timestamps();
        });
```
