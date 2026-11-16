Error with bare report when DateTime used as parameter value
```
In PhpValueFactory.php line 41:

  [RuntimeException]
  Cannot interpret PHP value "DateTime"

 ```

### Additional contract requirements

- Add a public class `PhpBench\Expression\Ast\UnrepresentableValueNode` whose constructor accepts any PHP value and whose `value()` method returns that value.
- `PhpBench\Expression\Ast\PhpValueFactory::fromValue($value)` must return an `UnrepresentableValueNode` wrapping `$value` for values that cannot be represented by the existing node types.
- Add a public class `PhpBench\Expression\NodePrinter\UnrepresentableValuePrinter` with a `print(Printer $printer, Node $node): ?string` method that returns `<type>`, where *type* is the PHP type of the wrapped value (for example `<object>`), or `null` when the node is not an `UnrepresentableValueNode`.
