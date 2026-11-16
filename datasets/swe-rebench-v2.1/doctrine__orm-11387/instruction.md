Error in ProxyFactory using cloned proxy entity with Enum field
### Bug Report

<!-- Fill in the relevant information below to help triage your issue. -->

|    Q        |   A
|------------ | ------
| BC Break    | no
| Version     | 3.1.0

#### Summary

<!-- Provide a summary describing the problem you are experiencing. -->
I'll use simulated example. We have 2 entities (Cart, Customer) with OneToOne join. Customer entity has PHP Enum field. I fetch Cart from database, get Customer (receive proxy object), make copy with clone. When I try to access data of cloned entity - there is fatal error:
`Typed property ReflectionProperty::$name must not be accessed before initialization` in Doctrine\ORM\Proxy\ProxyFactory line 237.
```
foreach ($class->getReflectionProperties() as $property) {
    [HIDDEN]
        continue;
    }
```
[HIDDEN]


#### Current behavior

<!-- What is the current (buggy) behavior? -->
Fatal error

#### How to reproduce

<!--
Provide steps to reproduce the bug.
If possible, also add a code snippet with relevant configuration, entity mappings, DQL etc.
Adding a failing Unit or Functional Test would help us a lot - you can submit one in a Pull Request separately, referencing this bug report.
-->
2 entities, enum object and example to reproduce:
```
<?php

namespace App\Entity;

use App\Repository\CartRepository;
use Doctrine\ORM\Mapping as ORM;

#[ORM\Entity(repositoryClass: CartRepository::class)]
class Cart
{
    #[ORM\Id, ORM\GeneratedValue, ORM\Column]
    private ?int $id = null;

    #[ORM\Column]
    private ?int $amount = null;

    #[ORM\OneToOne(inversedBy: 'cart', cascade: ['persist', 'remove'])]
    private ?Customer $customer = null;

    public function getId(): ?int
    {
        return $this->id;
    }

    public function getAmount(): ?int
    {
        return $this->amount;
    }

    public function setAmount(int $amount): static
    {
        $this->amount = $amount;

        return $this;
    }

    public function getCustomer(): ?Customer
    {
        return $this->customer;
    }

    public function setCustomer(?Customer $customer): self
    {
        $this->customer = $customer;

        return $this;
    }
}
```

```
<?php

namespace App\Entity;

use App\Enum\Type;
use App\Repository\CustomerRepository;
use Doctrine\DBAL\Types\Types;
use Doctrine\ORM\Mapping as ORM;

#[ORM\Entity(repositoryClass: CustomerRepository::class)]
class Customer
{
    #[ORM\Id, ORM\GeneratedValue, ORM\Column]
    private ?int $id = null;

    #[ORM\Column(length: 255)]
    private ?string $name = null;

    #[ORM\Column(type: Types::SMALLINT, nullable: true, enumType: Type::class, options: ['unsigned' => true])]
    private ?Type $type = null;

    #[ORM\OneToOne(mappedBy: 'customer')]
    private ?Cart $cart = null;

    public function getId(): ?int
    {
        return $this->id;
    }

    public function getName(): ?string
    {
        return $this->name;
    }

    public function setName(string $name): static
    {
        $this->name = $name;

        return $this;
    }

    public function getType(): ?Type
    {
        return $this->type;
    }

    public function setType(Type $type): static
    {
        $this->type = $type;

        return $this;
    }

    public function getCart(): ?Cart
    {
        return $this->cart;
    }

    public function setCart(?Cart $cart): self
    {
        // unset the owning side of the relation if necessary
        if (null === $cart && null !== $this->cart) {
            $this->cart->setCustomer(null);
        }

        // set the owning side of the relation if necessary
        if (null !== $cart && $cart->getCustomer() !== $this) {
            $cart->setCustomer($this);
        }

        $this->cart = $cart;

        return $this;
    }
}
```

```
<?php

namespace App\Enum;

enum Type: int
{
    case MALE = 1;
    case FEMALE = 2;
}
```

```
$cart = $repo->find(1);
$customer = clone $cart->getCustomer();
echo $customer->getName();
```


#### Expected behavior

<!-- What was the expected (correct) behavior? -->
No errors
