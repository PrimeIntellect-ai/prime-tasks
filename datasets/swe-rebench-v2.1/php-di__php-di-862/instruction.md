Wildcard definition for class in global namespace matches any namespace
The project I am working on has quite some classes defined in the global namespace.
When adding a wildcard definition for these classes, not only those classes are matched, but also matching class names in any namespace.
This is quite unexpected, since the documentation states:
> the wildcard does not match across namespaces

For example:

```
return [
    'Job*' => DI\autowire()->method('foo', 'bar'),
];
```
will call `foo('bar')` on class `JobDoSomething`, but also on class `SomeNamespace\JobScheduler`, which is not in the global namespace.

I am unfortunately on version 6.3.5, because PHP 7.2 ... But the code for matching the wildcard (regex) looks to be equal in both 6.4 and master.
