SingleImportPerStatementFixer does not temove braces when only single item
### Feature request

```php
use Foo\Bar\{Baz};
```

On the one hand this is a single import but on the other hand the braces `{}` denote this is a group (of one item). I think this fixer could handle this and remove the braces.

### Link to Discussion where feature request was formed

_No response_

### Contribution Checks

- [ ] I have verified if this feature request was already discussed
- [ ] I am familiar with ["Feature or bug?"](https://github.com/PHP-CS-Fixer/PHP-CS-Fixer/blob/master/feature-or-bug.rst)
