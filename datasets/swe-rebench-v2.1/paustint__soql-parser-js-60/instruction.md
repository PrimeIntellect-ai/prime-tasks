The field Format fails if it is in a query
<!--
  Please include the following classification.
  If your classification is not added, you can modify the list below
-->
- [ ] Feature
- [x] Bug Request

<!--If this is a bug, please include the steps to reproduce the bug-->
## Description
For AuraDefinitionBundle, there is a field named FORMAT which is incorrectly.

Example:
```sql
SELECT Id, CreatedById, CreatedDate, DefType, IsDeleted, Format,
	LastModifiedById, LastModifiedDate, AuraDefinitionBundleId, ManageableState,
	Source, SystemModstamp
FROM AuraDefinition
```

The field `Format` in the query causes it to fail because this is also a reserved keyword.

![image](https://user-images.githubusercontent.com/5461649/58042241-60bcaf80-7af7-11e9-9704-fde352072ad1.png)
