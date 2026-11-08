disallowedClasses does not work when nullable
Hello, I found out that nullable types are not reported by this extension.
```php
class MyClass
{
    public \DateTime $datetime; // is reported
    public ?\DateTime $datetime2; // does not report
}
```
