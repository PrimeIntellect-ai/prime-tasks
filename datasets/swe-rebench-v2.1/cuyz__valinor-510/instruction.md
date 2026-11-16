Unsealed array shapes not recognized
I have a constructor like following:

```php
final readonly class LocalizedStrings
{
    /** @param array{'en-US': string, ...array<string, string>} $localized */
    public function __construct(public array $localized)
    {
    }
}
```

The rationale here is: "`en-US` must always exist, while other values are optional, but still strings".

Valinor throws this:

```
assert(!$type instanceof UnresolvableType)

vendor/cuyz/valinor/src/Mapper/Tree/Shell.php:32
vendor/cuyz/valinor/src/Mapper/Tree/Shell.php:42
vendor/cuyz/valinor/src/Mapper/Tree/Builder/ObjectNodeBuilder.php:50
vendor/cuyz/valinor/src/Mapper/Tree/Builder/ObjectNodeBuilder.php:23
vendor/cuyz/valinor/src/Mapper/Tree/Builder/NativeClassNodeBuilder.php:39
vendor/cuyz/valinor/src/Mapper/Tree/Builder/CasterNodeBuilder.php:24
vendor/cuyz/valinor/src/Mapper/Tree/Builder/UnionNodeBuilder.php:37
vendor/cuyz/valinor/src/Mapper/Tree/Builder/InterfaceNodeBuilder.php:51
vendor/cuyz/valinor/src/Mapper/Tree/Builder/CasterProxyNodeBuilder.php:24
vendor/cuyz/valinor/src/Mapper/Tree/Builder/IterableNodeBuilder.php:26
vendor/cuyz/valinor/src/Mapper/Tree/Builder/StrictNodeBuilder.php:36
vendor/cuyz/valinor/src/Mapper/Tree/Builder/ErrorCatcherNodeBuilder.php:33
vendor/cuyz/valinor/src/Mapper/Tree/Builder/RootNodeBuilder.php:16
vendor/cuyz/valinor/src/Mapper/Tree/Builder/ObjectNodeBuilder.php:56
vendor/cuyz/valinor/src/Mapper/Tree/Builder/ObjectNodeBuilder.php:23
vendor/cuyz/valinor/src/Mapper/Tree/Builder/NativeClassNodeBuilder.php:39
vendor/cuyz/valinor/src/Mapper/Tree/Builder/CasterNodeBuilder.php:24
vendor/cuyz/valinor/src/Mapper/Tree/Builder/UnionNodeBuilder.php:37
vendor/cuyz/valinor/src/Mapper/Tree/Builder/InterfaceNodeBuilder.php:51
vendor/cuyz/valinor/src/Mapper/Tree/Builder/CasterProxyNodeBuilder.php:24
vendor/cuyz/valinor/src/Mapper/Tree/Builder/IterableNodeBuilder.php:26
vendor/cuyz/valinor/src/Mapper/Tree/Builder/StrictNodeBuilder.php:36
vendor/cuyz/valinor/src/Mapper/Tree/Builder/ErrorCatcherNodeBuilder.php:33
vendor/cuyz/valinor/src/Mapper/Tree/Builder/RootNodeBuilder.php:16
vendor/cuyz/valinor/src/Mapper/Tree/Builder/ListNodeBuilder.php:58
vendor/cuyz/valinor/src/Mapper/Tree/Builder/ListNodeBuilder.php:37
vendor/cuyz/valinor/src/Mapper/Tree/Builder/CasterNodeBuilder.php:24
vendor/cuyz/valinor/src/Mapper/Tree/Builder/UnionNodeBuilder.php:37
vendor/cuyz/valinor/src/Mapper/Tree/Builder/InterfaceNodeBuilder.php:37
vendor/cuyz/valinor/src/Mapper/Tree/Builder/CasterProxyNodeBuilder.php:24
vendor/cuyz/valinor/src/Mapper/Tree/Builder/IterableNodeBuilder.php:26
vendor/cuyz/valinor/src/Mapper/Tree/Builder/StrictNodeBuilder.php:36
vendor/cuyz/valinor/src/Mapper/Tree/Builder/ErrorCatcherNodeBuilder.php:33
vendor/cuyz/valinor/src/Mapper/Tree/Builder/RootNodeBuilder.php:16
vendor/cuyz/valinor/src/Mapper/Tree/Builder/ObjectNodeBuilder.php:56
vendor/cuyz/valinor/src/Mapper/Tree/Builder/ObjectNodeBuilder.php:23
vendor/cuyz/valinor/src/Mapper/Tree/Builder/NativeClassNodeBuilder.php:39
vendor/cuyz/valinor/src/Mapper/Tree/Builder/CasterNodeBuilder.php:24
vendor/cuyz/valinor/src/Mapper/Tree/Builder/UnionNodeBuilder.php:37
vendor/cuyz/valinor/src/Mapper/Tree/Builder/InterfaceNodeBuilder.php:51
vendor/cuyz/valinor/src/Mapper/Tree/Builder/CasterProxyNodeBuilder.php:24
vendor/cuyz/valinor/src/Mapper/Tree/Builder/IterableNodeBuilder.php:26
vendor/cuyz/valinor/src/Mapper/Tree/Builder/StrictNodeBuilder.php:36
vendor/cuyz/valinor/src/Mapper/Tree/Builder/ErrorCatcherNodeBuilder.php:33
vendor/cuyz/valinor/src/Mapper/Tree/Builder/RootNodeBuilder.php:16
vendor/cuyz/valinor/src/Mapper/TypeTreeMapper.php:44
vendor/cuyz/valinor/src/Mapper/TypeTreeMapper.php:25
```

The assertion trips on this type:

```
/var/www/wefox/vendor/cuyz/valinor/src/Mapper/Tree/Shell.php:31:
class CuyZ\Valinor\Type\Types\UnresolvableType#2174 (2) {
  private string $rawType =>
  string(58) "array{'en-US': string, ...array<non-empty-string, string>}"
  private string $message =>
  string(267) "The type `array{'en-US': string, ...array<non-empty-string, string>}` for parameter `LocalizedString::__construct($localized)` could not be resolved: Comma missing in shaped array signature `array{'en-US': string, 0: ...array`."
}
```

### Additional contract requirements

When mapping a value to the reported localized-string array shape, the `en-US` entry must be present and its value must be a string. Additional entries are allowed only when both their keys and values are strings.
