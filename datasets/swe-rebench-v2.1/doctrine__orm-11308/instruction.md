getAssociationMappedByTargetField on the owning side of a relation fails in 3.0
### BC Break Report


|    Q        |   A
|------------ | ------
| BC Break    | yes
| Version     | 3.0.0

#### Summary

Calling `Doctrine\ORM\Mapping\ClassMetadata::getAssociationMappedByTargetField` on a relation which is not an inverse side of a relation does not work anymore in 3.0

#### Previous behavior

In 2.x, the method returned `null` for such cases.

#### Current behavior

this assertion fails: https://github.com/doctrine/orm/blob/9acc70d5b8be55a6ac33e5c7313a124fa90dbe21/src/Mapping/ClassMetadata.php#L2467

#### How to reproduce

I found this when investigating a support question in the Symfony Slack channel. This BC break affects ApiPlatform: https://github.com/api-platform/core/blob/8a35ee20c7aaf03b5a3d96baf920e2c99c5ae0fd/src/Doctrine/Orm/Metadata/Resource/DoctrineOrmLinkFactory.php#L70

To reproduce it, call `getAssociationMappedByTargetField` for a field being the owning side of a relation.

### Additional contract requirements

- Calling `getAssociationMappedByTargetField()` with the name of an owning-side association throws a `LogicException`. It does not return `null`.
- Calling `getAssociationMappedByTargetField()` with the name of an inverse-side association returns the name of the field that the association is mapped by.
