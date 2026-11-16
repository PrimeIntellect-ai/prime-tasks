Endpoint listing
So far we provided two helpers for our API endpoints:
- CommandProvider that handles executing CQRS commands, it allows writing an Entity
- QueryProvider that handles requesting CQRS queries, it allows reading an Entity

We lack something though to build a REST APIs completely, it is listing. Mostly because so far we never needed a CQRS query to perform this operation. We should provide a helper to help building the listing APIs as well.

Two possible solutions (at least, open to other suggestions):
- rely on the existing QueryProvider but it means we'll need to add a CQRS query on all the entities that are missing it (basically all of them)
- provide a third CollectionProvider helper that could be base on our existing Doctrine query builders which are already implemented and used by the grid system (so all the migrated pages)

### Additional contract requirements

Add two public operation classes in the `PrestaShopBundle\ApiPlatform\Metadata` namespace:

- `CQRSQueryCollection`, whose default provider is `PrestaShopBundle\ApiPlatform\Provider\QueryProvider`.
- `DQBPaginatedList`, whose default provider is `PrestaShopBundle\ApiPlatform\Provider\QueryListProvider`.

Both classes use the `GET` method (`METHOD_GET`) and accept `uriTemplate` and `extraProperties` constructor parameters. Both expose `getProvider()`, `getMethod()`, `getUriTemplate()` and `getExtraProperties()`.

`CQRSQueryCollection` additionally accepts the named constructor parameters `scopes`, `CQRSQuery`, `CQRSQueryMapping` and `ApiResourceMapping`, and exposes `getScopes()`, `getCQRSQuery()`, `getCQRSQueryMapping()` and `getApiResourceMapping()`.

`DQBPaginatedList` additionally accepts the named constructor parameters `scopes`, `ApiResourceMapping` and `queryBuilder`, and exposes `getScopes()`, `getApiResourceMapping()` and `getQueryBuilder()`.

Each of these values is exposed by its getter whether it was provided as the corresponding named constructor argument or under the same key of `extraProperties`.

Constructor-provided scopes merge with scopes provided in `extraProperties`: the scopes from `extraProperties` are kept first in their existing order, then the constructor-provided scopes are appended in their order, omitting duplicates. The merged scopes are exposed by `getScopes()` and by `getExtraProperties()` under the `scopes` key. `withScopes()` returns a clone whose scopes are replaced by the given scopes.

`withCQRSQuery()`, `withCQRSQueryMapping()`, `withApiResourceMapping()` and `withQueryBuilder()` return updated clones without modifying the original operation or its other values.

When a constructor argument conflicts with the same key in `extraProperties`, throw `ApiPlatform\Exception\InvalidArgumentException` with the exact message:

- `Specifying an extra property CQRSQuery and a CQRSQuery argument that are different is invalid` for `CQRSQuery`,
- `Specifying an extra property CQRSQueryMapping and a CQRSQueryMapping argument that are different is invalid` for `CQRSQueryMapping`,
- `Specifying an extra property ApiResourceMapping and a ApiResourceMapping argument that are different is invalid` for `ApiResourceMapping`.
