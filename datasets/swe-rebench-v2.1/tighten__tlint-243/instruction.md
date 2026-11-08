PHP 8 Attributes are recognized as unused import
Given the following file:
```php
<?php

namespace App\Utility\Game\DTO;

use Spatie\DataTransferObject\Attributes\Strict;
use Spatie\DataTransferObject\DataTransferObject;

#[Strict]
class UnitDTO extends DataTransferObject
{
    /** @var string[] */
    public array $possible_orders;
    public string $space;
}
```

I'm getting the following error:
```
Lints for /home/alexw/Code/dnw/zenvoy/app/Utility/Game/DTO/UnitDTO.php
============
! There should be no unused imports.
5 : `use Spatie\DataTransferObject\Attributes\Strict;`
```

I would expect tlint to recognize imports. I will try to provide a fix for this.
