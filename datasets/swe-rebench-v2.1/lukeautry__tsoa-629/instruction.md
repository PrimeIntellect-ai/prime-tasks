Aliased void Api Response types use 200 response instead of 204
## Sorting

* **I'm submitting a ...**
  - [x] bug report
  - [ ] feature request
  - [ ] support request

* I confirm that I
  - [x] used the [search](https://github.com/lukeautry/tsoa/search?type=Issues) to make sure that a similar issue hasn't already been submit

## Expected Behavior
<!--- Tell us what should happen -->
<!--- If this is related to swagger/OpenAPI files, then please include swagger.yaml that you wish tsoa had generated  -->
```yaml
     "/assets/v1/{id}": {
      "delete": {
        "operationId": "deleteAsset",
        "responses": {
          "204": {
            "content": {
              "application/json": {}
            },
            "description": "No content"
          },
```
<!--- If this is related to a TypeScript issue, then include the way that you expected to be able to write the code  -->
```ts

    type AssetDeleteResponseType = void;

    public async delete(
        id: string,
        @Request() request: express.Request,
    ): Promise<AssetDeleteResponse>
```

## Current Behavior
<!--- Tell us what happens instead of the expected behavior -->
<!--- If this is related to swagger/OpenAPI files, then please include swagger.yaml that tsoa actually generated  -->
```yaml
{
  "components": {
    "examples": {},
    "headers": {},
    "parameters": {},
    "requestBodies": {},
    "responses": {},
    "schemas": {
      "AssetDeleteResponse": {},
    },
    "paths": {
     "/assets/v1/{id}": {
      "delete": {
        "operationId": "deleteAsset",
        "responses": {
          "200": {
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/AssetDeleteResponse"
                }
              }
            },
            "description": "Ok"
          },
```
<!--- If this is related to a TypeScript issue, then include the way that you had to write the code  -->
```ts
    public async delete(
        id: string,
        @Request() request: express.Request,
    ): Promise<void> {
```

## Possible Solution
[HIDDEN]  This means that the type alias doesn't carry over to any remote clients however at least its accurate.

### Workaround
Use void directly in api responses that return void.  This isn't a bad workaround but I lost some time to the unexpected behavior so I decided to go ahead and file it.

## Context (Environment)
Version of the library: 3.0.2
Version of NodeJS: 12.12.0
* Confirm you were using yarn not npm: [x]

### Additional contract requirements

- When an API method's response type resolves through one or more type aliases to `void`, its generated OpenAPI response must use status `204` with the description “No content,” rather than status `200`.
- The 204 response for an aliased-void API method includes an empty `application/json` content object.
