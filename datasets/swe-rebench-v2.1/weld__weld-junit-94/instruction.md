Injection problem in test class for contextual instances
If you try to inject an instance of a requestscoped bean in a test class with @Inject annotation, it fails with an error: context not active exception.

Possible solution:
Looking at code I have made a change in  [HIDDEN] and it works well. Now I can inject a contextual instance without problems.

Best regards
Jacopo

### Additional contract requirements

- When a test instance is registered for CDI injection, its `@Inject` members must be populated after the container starts. Injection of contextual or request-scoped beans must not fail because the relevant context is inactive when that context has been activated.
