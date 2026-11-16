[ConfigTransformer] Invalid invokable factory transformation
Initially reported [here](https://twitter.com/_Codito_/status/1561727341176520706). Factory that uses `__invoke()` method was transformed to invalid format (red), it should be without `[]` wrapping (green):

```diff
- ->factory([service(FooFactory::class)])
+ ->factory(service(FooFactory::class))
```

[Symfony docs](https://symfony.com/doc/current/service_container/factories.html#invokable-factories).

## Expected behavior

Invokable factories are transformed with proper syntax.
