Cannot lookup property of namespace in parent class
**Describe the bug**
The mapper does not correctly lookup the namespace of a property in a parent class correctly

**To Reproduce**
I have something like these classes:
```php
<?php

declare(strict_types = 1);

namespace Foo;

use Bar\UpdateCustomer;

class Customer extends UpdateCustomer
{
}

```

```php
<?php

declare(strict_types = 1);

namespace Bar;

class UpdateCustomer
{
    /** @var null|CustomerState */
    public $customerState;

}

```

```php
<?php

declare(strict_types = 1);

namespace Bar;

class CustomerState
{
    /** @var null|string */
    public $description;
}
```

**Expected behavior**
The properties should be mapped correctly

**Stacktrace**
Unable to map to CustomerState

**Environment (please complete the following information):**
 - PHP: 7.2

**Additional context**

It seems the Bar namespace is not evaluated with the lookup for the CustomerState.
If I just a "use Bar\CustomerState;" to the initial customer class it works.
