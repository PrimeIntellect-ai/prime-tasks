Perform query param validation within BaseService
We've a few badges which validate query params by invoking `_validateQueryParams` on BaseService.

If we provided the route with a Joi schema instead of an array of names, we could validate these _within_ BaseService instead – i.e. prior to invoking `handle()`.

If #2675 hasn't been completed yet, we could use a placeholder `Joi.object().required()` for those services in the meantime.

### Additional contract requirements

- Each route supplies its Joi query-parameter schema through `queryParamSchema`. Query parameters are validated against that schema before the service handler runs. A parameter that fails validation produces an error badge whose message is `invalid query parameter: <name>`.
- The AppVeyor tests badge accepts the query parameters `compact_message`, `passed_label`, `failed_label` and `skipped_label`.
- The Mozilla Observatory badge accepts the `publish` query parameter.
