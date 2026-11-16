Invalid map in collection.
After update PHPStan to version 1.5.4, the map function of collection does not work anymore.

Example:

```php

use Doctrine\Common\Collections\ArrayCollection;
use Doctrine\Common\Collections\Collection;

class Item {

    private ?Parent  $parent = null;

    public function setParent(?Parent $parent): void
    {
        $this->parent = $parent;
    }
}

class Parent {

    /**
     * @var Collection<int, Item>
     */
    private Collection $items;

    public function __construct()
    {
        $this->items = new ArrayCollection();
    }

    public function __clone()
    {
        $this->items = $this->items->map(
            fn (Item $item): Item => (clone $item)->setParent($this)
        );
    }
}
```

The follwing error is raised:

```
------ -------------------------------------------------------------------------------------------------
  Line   src\Parent.php
 ------ -------------------------------------------------------------------------------------------------
  81     Property Parent::$items (Doctrine\Common\Collections\Collection<int, Item>)
         does not accept Doctrine\Common\Collections\ReadableCollection<int, Item>.
         🪪  assign.propertyType
 ------ -------------------------------------------------------------------------------------------------
```

Maybe, the `Collection` and `ArrayCollection` stubs must be also updated.
