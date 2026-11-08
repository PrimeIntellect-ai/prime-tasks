Model namespace not appended in the generated model factory class
<!-- PLEASE COMPLETE THIS TEMPLATE -->

- Laravel Version: 8.62.0
- PHP Version: 7.4.5
- Blueprint Version: 2.0.0
- Platform: Mac | Windows | Linux

### Issue:
When building a model with a namespace, the generated model factory does not append the provided namespace.

```php
<?php

namespace Database\Factories; // must be: namespace Database\Factories\Admin;
```

### draft.yaml:
```yaml
Admin\User:
    name: string
```
