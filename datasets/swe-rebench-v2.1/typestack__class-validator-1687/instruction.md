The names of the decorators are lost in the MetadataStorage
### Description

Since the 0.12.x update, the names of the decorators are lost when stored.
For example, when the `IsString` decorator is used, the metadata store a new entry with the type `customValidation` instead of `isString`. This seems to apply to all decorators, because of this line: https://github.com/typestack/class-validator/blob/1955250de64d76504df465aa02076a2e5b219bb7/src/register-decorator.ts#L80.

### Reproduction

Inspect the stored metadata with `getMetadataStorage().getTargetValidationMetadatas` and you'll see that all entries' `type`s are `customValidation`, instead of their decorator names.

### Environment

- [ ] nodejs: 10.18.1
- [ ] browser: no
- [ ] framework/library: standalone

**class-validator version:** <code>0.12.2</code>

### Additional contract requirements

- Each validation metadata entry stored for a property must keep the name of the decorator that registered it, exposed as the entry's `name` property. For example, after `@IsString()` is applied to a property, the stored entry for that property has the name `isString`. A custom decorator registered with `registerDecorator` under a name keeps that name as well.
