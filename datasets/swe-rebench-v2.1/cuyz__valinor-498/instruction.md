How to serialize object collection, ArrayObject used
I have this main Entity:

```
<?php

declare(strict_types=1);

namespace App\ApiModule\Entity\V1\ExpeditionPacking;

use Spatie\TypeScriptTransformer\Attributes\TypeScript;

#[TypeScript]
class CompletionPackageEntity
{

	public function __construct(
		/**
		 *
		 * @var string[]
		 */
		public array                                 $weightOfItems,
		/**
		 * @var ArrayOfCompletionPackageDokladEntity|null
		 */
		public ?ArrayOfCompletionPackageDokladEntity $data,
		public array                                 $EANtoProduktVarianta,
		public bool                                  $iAmNotOwner
	)
	{

	}
```

now code for ArrayOfCompletionPackageDokladEntity

```
<?php

declare(strict_types=1);

namespace App\ApiModule\Entity\V1\ExpeditionPacking;

use Romanmatena\PhpTools\Collections\ArrayCollection;
use Spatie\TypeScriptTransformer\Attributes\TypeScript;

#[TypeScript]
class ArrayOfCompletionPackageDokladEntity extends ArrayCollection
{
```

now ArrayCollection

```
<?php

namespace Romanmatena\PhpTools\Collections;

abstract class ArrayCollection extends \ArrayObject implements ICollection, \Traversable, \JsonSerializable
{
	/**
	 * @return array|object
	 */
	public function jsonSerialize(): array|object
	{
		return $this->toArray();
	}
```

if i use json_encode then data includes the objects in ArrayCollection but if i use normalizer, data is empty

```
$normalizer = (new \CuyZ\Valinor\MapperBuilder())
				->normalizer(\CuyZ\Valinor\Normalizer\Format::json());

			$content = $normalizer->normalize($completionPackageEntity);
```

do i missing something?

[HIDDEN]

### Additional contract requirements

- When normalizing an `ArrayObject` or a subclass, the result must contain its stored entries, preserving their keys and recursively normalizing their values, rather than producing an empty object.
