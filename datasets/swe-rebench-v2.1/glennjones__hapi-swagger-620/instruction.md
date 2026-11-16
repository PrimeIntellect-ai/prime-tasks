Make the "api" tag used to filter routes configurable
It would be really useful if you could configure the tag used to filter the routers included in the OpenAPI spec file, when setting up the hapi-swagger plugin. This would enable configuring two docs for different APIs within the same HapiJS server and thus being able to have different descriptions and global attributes.

I could create a PR.

### Additional contract requirements

- The plugin configuration option `routeTag` selects the tag used to filter routes in the generated OpenAPI document: routes tagged with that value are included, and routes without it are excluded.
