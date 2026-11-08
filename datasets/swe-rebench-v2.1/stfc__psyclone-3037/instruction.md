The `is_writen/read/accessed_before` from SingleVariableAccessInfo does not respected control flow
This is because it uses the _location in AccessType, which is mostly a syntactic location but with the assignment order switched. But it means what calling these methods will result to bugs if conditions and loops are involved.

We now have the DefinitionUseChain for knowing the proper usage order, and we already have position for syntactic location, so I propose removing these methods and the _location altogether.

### Additional contract requirements

The location-based API must be removed entirely (not merely deprecated or kept
for backwards compatibility). In particular, the following public names must no
longer exist:

- ``SingleVariableAccessInfo.is_written_before``
- ``SingleVariableAccessInfo.is_read_before``
- ``SingleVariableAccessInfo.is_accessed_before``
- ``SingleVariableAccessInfo.add_access_with_location``
- the ``location`` property of ``AccessInfo``
