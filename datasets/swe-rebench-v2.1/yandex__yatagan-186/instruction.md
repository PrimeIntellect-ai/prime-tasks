[KSP2] HeavyTest failures because of wildcards
In code of generated component there are a few places where instead of
```kotlin
  @Override
  public Lazy<Node_122> getGet_24() {
    return new CachingProviderImpl(this, 23);
  }
```
generates this:
```kotlin
  @Override
  public Lazy<? extends Node_122> getGet_24() {
    return new CachingProviderImpl(this, 23);
  }
```

Reproduces only with KSP2 even with latest version at the moment of issue creation (`2.1.20-2.0.0`).
