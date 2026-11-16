[Toggle PSR-11 Factories] Add static version to RemoveFeatureFactory
**Epic:** https://github.com/pheature-flags/pheature-flags/issues/122 Toggle PSR-11 Factories
**Package:** https://github.com/pheature-flags/toggle-psr11-factories

**Description:**

Following the example defined in the issue https://github.com/pheature-flags/pheature-flags/issues/122, create a static version of the RemoveFeatureFactory class.

### Additional contract requirements

- Add a public static method `create(FeatureRepository $featureRepository): RemoveFeature` to `Pheature\Crud\Psr11\Toggle\RemoveFeatureFactory` (package `toggle-crud-psr11-factories`), where `FeatureRepository` is `Pheature\Core\Toggle\Write\FeatureRepository` and `RemoveFeature` is `Pheature\Crud\Toggle\Handler\RemoveFeature`. The returned handler must use the exact `FeatureRepository` instance supplied by the caller.
- The existing invokable `__invoke(ContainerInterface $container): RemoveFeature` must keep obtaining the `FeatureRepository` from the container by requesting `FeatureRepository::class` and return a `RemoveFeature`.
