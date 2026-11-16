[7.7.0] `getSourceModuleName` should only be called on `MemberExpression` or `Identifier`
After updating, I get that error:

```
Build Error (broccoli-persistent-filter:EslintValidationFilter) in components/application-header.ts

`getSourceModuleName` should only be called on `MemberExpression` or `Identifier`
Occurred while linting /home/boris/project/app/components/application-header.ts:24
```

That line is as follows:

```typescript
@classic
@tagName('nav')
@classNames('navbar', 'navbar-default', 'navbar-fixed-top')
export default class extends Component.extend(ResizeAware) {
```

The last line is `24`.
