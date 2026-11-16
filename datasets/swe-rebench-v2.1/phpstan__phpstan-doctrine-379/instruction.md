Generated fields not correctly treated as written by Doctrine
Having a generated field in an entity:
```
    #[Column(type: Types::DATETIME_MUTABLE, insertable: false, updatable: false,
        columnDefinition: 'datetime GENERATED ALWAYS AS (DATE_ADD(Start, INTERVAL Hours * 60 MINUTE))',
        generated: 'ALWAYS')]
    private \DateTimeInterface $end;
```
Obviously only with a plain getter:
```
    public function getEnd(): \DateTimeInterface
    {
        return $this->end;
    }
```
Makes phpstan not a happy camper:
```
  75     Property WorkEntry::$end is never written, only read.
         💡 See: https://phpstan.org/developing-extensions/always-read-written-properties
```
Solution is to properly parse the `generated` property of the attribute, and consider the property always-written when `ALWAYS` or `INSERT`, ref https://www.doctrine-project.org/projects/doctrine-orm/en/2.13/reference/annotations-reference.html#column

Feature has actually been in Doctrine ORM since 2.11: https://www.doctrine-project.org/2022/01/11/orm-2.11.html
