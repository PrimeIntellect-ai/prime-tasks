Column: wrong parsing of fieldname from sortby/filterBy VE
**Describe the defect**
As we're migrating all of our columns to use `UIColumn#field` instead of sortBy/filterBy. I recently discovered a bug when sortBy contains an expression like: `#{i18n[row][property]}`, it resolves a fieldname `i18n[row][property]` which obvisouly turn into a bug later on. Same goes for `p:columns` with `#{i18n[row][column[property]]}` (`row][column[property]` being resolved). Basically, our regexes are not restrictive enough, it should handle two very basic cases:

- `#{car.name}` -> name (for static columns)
- `#{car[column.property]}` -> name (for dynamic columns)

Beyond that, it gets too complicated to resolve field

**Environment:**
 - PF Version: 10.0
 - JSF + version:  Mojarra 2.2.20
 - Affected browsers: Chrome

**To Reproduce**
Steps to reproduce the behavior:
1. For static columns: Use a VE like `#{i18n[row][property]}` for sortBy
2. For dynamic columns: Use a VE like `#{i18n[row][column[property]]}` for sortBy

**Expected behavior**
Where field is not set, resolving field from these expressions should return null

### Additional contract requirements

When a column has no explicit field, sort and filter metadata must use the field resolved from its sortBy or filterBy value expression. The static expression `#{car.name}` resolves to `name`, and the dynamic expression `#{car[column.property]}` resolves to the property value represented by the bracket expression. For the reproduced multi-index expressions `#{i18n[row][property]}` and `#{i18n[row][column[property]]}`, the field exposed by sort and filter metadata must be null.
