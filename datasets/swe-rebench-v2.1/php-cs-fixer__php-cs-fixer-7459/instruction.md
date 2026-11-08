Support for `FullyQualifiedStrictTypesFixer` in classes' `extends` part
When using the directive `fully_qualified_strict_types`, the `class extends` should be shortened when it's possible.

#### The PHP version you are using (`$ php -v`):
=> 7.2.15

#### PHP CS Fixer version you are using (`$ php-cs-fixer -V`):
=> 2.14.1

#### If applicable, please provide minimum samples of PHP code (as plain text, not screenshots):
 * before running PHP CS Fixer (no changes):
```php
<?php

namespace Foo\Bar;

class SomeClass extends \Foo\Bar\Izumi
{
}
```

 * with the changes you expected instead:
```php
<?php

namespace Foo\Bar;

class SomeClass extends Izumi
{
}
```

FQCN transform for static access (property/constant fetch, method call)
## Feature request
The following isn't currently doable by any rule:

```diff
+use pocketmine\network\mcpe\protocol\types\LevelSoundEvent;

class A{
	public function encode(Vector3 $pos) : array{
-		return [LevelSoundEventPacket::nonActorSound(\pocketmine\network\mcpe\protocol\types\LevelSoundEvent::BLOCK_BARREL_CLOSE, $pos, false)];
+		return [LevelSoundEventPacket::nonActorSound(LevelSoundEvent::BLOCK_BARREL_CLOSE, $pos, false)];
	}
}
```

### Additional contract requirements

The fixer shortens a fully qualified symbol reference only when the referenced
symbol is already imported via a `use` statement or belongs to the current
namespace. It does not add `use` statements. In the static-access example above,
the `use pocketmine\network\mcpe\protocol\types\LevelSoundEvent;` declaration is
present in the input, and the fixer shortens the fully qualified reference to
`LevelSoundEvent::BLOCK_BARREL_CLOSE`.
