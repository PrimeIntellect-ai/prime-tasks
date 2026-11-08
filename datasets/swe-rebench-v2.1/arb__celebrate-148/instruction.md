Subsequent calls no longer validating on upgrade to v11
- `node` version - 12.9.1
- `celebrate` version - 11.0.0-rc2
- `joi` version (via `npm ls --depth=0 | grep joi`) - 16.1.7

My `joi` schema looks like this:
```js
exports.getAllProjectParametersSchema = {
  query: Joi.object({
    limit: Joi.number()
      .integer()
      .default(50),
    start: Joi.number()
      .integer()
      .default(0),
    sort: Joi.string()
      .valid(
        'asset_name',
        'asset_name:asc',
        'asset_name:desc',
        'updated_by',
        'updated_by:asc',
        'updated_by:desc',
      )
      .default('updated_at:desc')
  }),
  params: Joi.object({
    project_id: Joi.number()
      .integer()
      .required()
  })
};
```

Here is an example value that is not working as expected:
Route being checked:
```js
projectParameterRouter
  .route('/api/projects/:project_id/parameters')
  .get(celebrate(getAllProjectParametersSchema), getAllProjectParameters)
  .all(methodNotAllowed);
```
Example api call for which celebrate should set the default queries:
```js
'/api/projects/1/parameters'
```

The issue I am having with `celebrate` is:

The code was working ok in v10.1.0. I upgraded it to allow use of joi-v16 and the failover() method to set the queries to predefined values if they don't meet the schema.
However, I'm running into validation issues before changing any of the code.
I'm using Jest to test the api and for the first value in the test the default values are updating req.query. However, all subsequent tests in the same run do not have their default values updated and do not appear to be getting validated. Equally all tests when run in isolation work as expected.
The same happens when running the api locally - the first call to the endpoint works, but subsequent calls do not (as per the tests).
I don't think there is an issue with the schema vs the upgraded joi version as its validating the first request ok.
Any ideas what would be causing this? Thanks.
