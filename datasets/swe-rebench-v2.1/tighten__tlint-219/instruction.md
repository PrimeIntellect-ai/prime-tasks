Imports are marked unused when they're only used as part of a union type
Given this file tlint lints `DateTimeInterface` as an unused import:

```php
<?php

namespace App\Quotes;

use DateTimeInterface;

class Quote
{
    public function construct(string|DateTimeInterface $start, string|DateTimeInterface $end)
    {
        // ...
    }
}
```

If I remove `string|` so the type hint is just `DateTimeInterface` on its own, it works.

Using the Sublime plugin:

<img width="940" alt="Screen Shot 2021-02-03 at 2 14 06 PM" src="https://user-images.githubusercontent.com/18192441/106797215-54111f80-662a-11eb-84d2-abd30769a471.png">
