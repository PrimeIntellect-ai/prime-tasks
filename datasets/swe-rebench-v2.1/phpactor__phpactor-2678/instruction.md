Initialised properties don't appear in LSP document symbols
Given this class:

```php
<?php

namespace App;

class Foo
{
    private string $uninitialised;

    private string $initialised = '';
}
```

.. I see these document symbols (using [Trouble](https://github.com/folke/trouble.nvim) in Neovim):

```
  Document Symbols  2
   └╴  src/App/Foo.php  2
     └╴  Foo class Foo [5, 7]
       └╴  uninitialised private string $uninitialised; [7, 20]
```

Note that the property `$initialised` doesn't appear in the list of document symbols.
