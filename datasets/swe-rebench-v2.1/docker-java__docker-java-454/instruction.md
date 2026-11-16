non-void setters for AuthConfig
Hope class shouldn't match java beans and can provide fluent setters.

### Additional contract requirements

- `AuthConfig` (in `com.github.dockerjava.api.model`) must provide fluent configuration methods `withUsername(String)`, `withPassword(String)`, `withEmail(String)` and `withRegistryAddress(String)`. Each sets the corresponding value and returns the same `AuthConfig` instance it was called on, so calls can be chained.
- `AuthConfig` must provide `getRegistryAddress()`, returning the configured registry address and defaulting to `AuthConfig.DEFAULT_SERVER_ADDRESS` (`"https://index.docker.io/v1/"`) when it has not been set.
- `AuthConfig` must not expose writable JavaBeans properties, and must not expose any public method whose name follows the `setXxx` setter convention, even if JavaBeans introspection would not treat that method as a property writer.
