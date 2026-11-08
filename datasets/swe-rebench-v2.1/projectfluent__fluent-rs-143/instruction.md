Add support for `FluentBundle::add_resource` allowOverrides
JS implementation allows to set `allowOverrides` to true and allow for new resources to override messages in bundle, see https://github.com/projectfluent/fluent.js/pull/332

### Additional contract requirements

`FluentBundle` must provide the override behavior through `add_resource_overriding`. Adding a resource through the ordinary `add_resource` path must leave an existing message with the same identifier unchanged and report the duplicate; using `add_resource_overriding` must make the later message the one returned for that identifier.
