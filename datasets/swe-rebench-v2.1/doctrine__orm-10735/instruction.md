Extra update for self-referencing Many-To-One with NONE generator strategy during persist
### Bug Report

<!-- Fill in the relevant information below to help triage your issue. -->

|    Q        |   A
|------------ | ------
| BC Break    | no
| Version     | 2.6.4

#### Summary

Using a self-referencing entity with a Many-To-One relationship set during the `__construct()` call with a `NONE` strategy for id generation leads to two queries:
- first an INSERT
- then an UPDATE for the relationship

#### Current behavior

- this requires the relationship related column to accept `NULL` for the first `INSERT`

`[2019-10-23 16:04:21] doctrine.DEBUG: INSERT INTO organization (id, legal_parent_id) VALUES (?, ?, ?, ?, ?, ?, ?) {"1":"[object] (Ramsey\\Uuid\\Uuid: \"c68555b0-f5ae-11e9-914e-38baf82a0624\")","2":null} []`

- this leads to a useless `UPDATE` query

`[2019-10-23 16:04:21] doctrine.DEBUG: UPDATE organization SET legal_parent_id = ? WHERE id = ? ["[object] (Ramsey\\Uuid\\Uuid: \"c68555b0-f5ae-11e9-914e-38baf82a0624\")","[object] (Ramsey\\Uuid\\Uuid: \"c68555b0-f5ae-11e9-914e-38baf82a0624\")"] []`

#### How to reproduce

```sql

CREATE TABLE `organization` (
  `id` binary(16) NOT NULL COMMENT '(DC2Type:uuid_binary_ordered_time)',
  `legal_parent_id` BINARY(16) NOT NULL COMMENT '(DC2Type:uuid_binary_ordered_time)',
  PRIMARY KEY (`id`),
  CONSTRAINT FK_C1EE637C9EB3F521 FOREIGN KEY (legal_parent_id) REFERENCES organization (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

```

```php
<?php

declare(strict_types=1);

namespace App\Entity;

use Doctrine\Common\Collections\ArrayCollection;
use Doctrine\Common\Collections\Collection;
use Doctrine\ORM\Mapping as ORM;

/**
 * An Organization
 * @ORM\Entity(repositoryClass="App\Repository\OrganizationRepository")
 */
class Organization
{
    public function __construct()
    {
        $factory = clone \Ramsey\Uuid\Uuid::getFactory();
        $codec = new \Ramsey\Uuid\Codec\OrderedTimeCodec(
            $factory->getUuidBuilder()
        );
        $factory->setCodec($codec);
		$this->id = $factory->uuid1();
        $this->legalParent = $this;
        parent::__construct();
    }

    /**
     * Unique ID of the entity
     *
     * @ORM\Id()
     * @ORM\GeneratedValue(strategy="NONE")
     * @ORM\Column(type="uuid_binary_ordered_time", unique=true)
     */
    private $id;

    public function getId(): ?string
    {
        return $this->id->__toString();
    }

    /**
     * @var self
     * @ORM\ManyToOne(targetEntity="App\Entity\Organization")
     * @ORM\JoinColumn(fieldName="legal_parent_id", referencedColumnName="id", nullable=false)
     */
    protected $legalParent;

    public function getLegalParent(): self
    {
        return $this->legalParent;
    }

    public function setLegalParent(self $legalParent): self
    {
        $this->legalParent = $legalParent;

        return $this;
    }
}

```

#### Expected behavior

- Only the `INSERT` query with `legal_parent_id` not `NULL`

`[2019-10-23 16:04:21] doctrine.DEBUG: INSERT INTO organization (id, legal_parent_id) VALUES (?, ?, ?, ?, ?, ?, ?) {"1":"[object] (Ramsey\\Uuid\\Uuid: \"c68555b0-f5ae-11e9-914e-38baf82a0624\")","2":[object] (Ramsey\\Uuid\\Uuid: \"c68555b0-f5ae-11e9-914e-38baf82a0624\")} []`

#### Possible solution

This comes from `vendor/doctrine/orm/lib/Doctrine/ORM/Persisters/Entity/BasicEntityPersister.php`

![image](https://user-images.githubusercontent.com/3177556/67414724-f3400e00-f5c3-11e9-9d4b-abb4bc298bf0.png)

[HIDDEN]

I can provide a PR if you want
