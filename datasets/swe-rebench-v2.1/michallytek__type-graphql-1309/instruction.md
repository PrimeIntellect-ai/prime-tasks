@ObjectType() with a double underscore in the `name` argument prevents field resolvers from executing
**Describe the Bug**
When the name argument string contains a double underscore, field resolvers for this objectType fail to execute `@ObjectType('product__tag')`

**To Reproduce**
```
@ObjectType('product__tag')
class ProductTagType {
  @Field()
  public id: string;
}

@Resolver(() => ProductTagType)
class ProductTagResolver
  // this does not execute
  @FieldResolver(() => String)
  public name(): string {
    return 'hello';
  }
}
```

```
    {
      "message": "Cannot return null for non-nullable field product__tag.name.",
    }
```

**Expected Behavior**
name strings with double underscore should not prevent field resolvers from executing correctly

**Environment (please complete the following information):**

- OS: MacOS
- Node v12.13.1
- Package version 1.1.1
- TypeScript version 4.2.4
