The method AugmentedModel::wrapModelAccessor resolves Attribute getter without passing params $value and $attributes
### Description

On this line [AugmentedModel.php#L189](https://github.com/statamic-rad-pack/runway/blob/3bb86435aac2a8e351bfcc42f8d6f019eb58e7d2/src/Data/AugmentedModel.php#L189) the attribute getter is called without passing any params. This causes the method to break when one of those params is required.

Changing the method to something like this resolves the issue:
```
[HIDDEN]
```

Before I open an PR I wanted to check if this was setup like this intentionally.

### Steps to reproduce

1. Create a model with an Attribute that uses a getter whit an value, for example:
```php
 public function slug(): Attribute
    {
        return Attribute::make(
            set: function($input) {
                $slug = Str::slug($input);
                $found = 0;
                while (Club::where('slug', '=', $slug)->count()) {
                    $found++;
                    $slug = Str::slug($input . "-{$found}");
                }

                return $slug;
            },
            get: fn (?string $value) => $value,
        );
    }
```
2. Do something that creates the `AugmentedModel`. For example in a entry that has a Runway model (`$my_model`) linked trough an `BelongsTo` field.
```
{{ $my_model->value() }}
```
calling `->value()` causes the method to break as it is creating the AugmentedModel.

### Environment

Environment
Laravel Version: 11.20.0
PHP Version: 8.3.12
Composer Version: 2.7.7
Environment: local
Debug Mode: ENABLED
Maintenance Mode: OFF
Timezone: UTC
Locale: nl

Cache
Config: NOT CACHED
Events: NOT CACHED
Routes: NOT CACHED
Views: CACHED

Drivers
Broadcasting: log
Cache: file
Database: mysql
Logs: stack / single
Mail: smtp
Queue: sync
Session: file

Livewire
Livewire: v3.5.4

Sentry
Enabled: MISSING DSN
Environment: local
Laravel SDK Version: 4.8.0
PHP SDK Version: 4.9.0
Release: NOT SET
Sample Rate Errors: 100%
Sample Rate Performance Monitoring: NOT SET
Sample Rate Profiling: NOT SET
Send Default PII: DISABLED

Statamic
Addons: 6
Sites: 2 (Nederlands, Engels)
Stache Watcher: Enabled
Static Caching: Disabled
Version: 5.22.0 PRO

Statamic Addons
alt-design/alt-redirect: 1.3.2
alt-design/alt-seo: 1.2.1
alt-design/alt-sitemap: 1.2.2
doefom/currency-fieldtype: 1.4.1
statamic-rad-pack/runway: dev-morphmany
statamic/eloquent-driver: 4.15.2

Statamic Eloquent Driver
Asset Containers: file
Assets: eloquent
Blueprints: file
Collection Trees: eloquent
Collections: file
Entries: eloquent
Forms: file
Global Sets: file
Global Variables: eloquent
Navigation Trees: eloquent
Navigations: file
Revisions: file
Sites: file
Taxonomies: file
Terms: eloquent
Tokens: eloquent

### Additional contract requirements

- When an Eloquent Attribute getter declares `$value` and/or `$attributes` parameters, accessing the corresponding augmented model value must succeed. Those parameters must represent the current attribute value and the model's attributes, respectively.
