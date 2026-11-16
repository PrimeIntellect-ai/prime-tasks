`getOpenApiDocumentation()` not correctly create the documentation
### Describe the bug

I encountered an issue with the `getOpenApiDocumentation` method.

We have contracts that have a same path but different methods. When we call the above method on the contracts it only shows one method with one path. So for example the /trainStatus has a `GET` and `PUT` method, but it only shows one of them. It shows the method that was added last.

### Reproduction

Contracts:

```typescript
export const getTrainStatusContract = new ApiGatewayContract({
  id: 'get-train-status',
  path: '/trainStatus',
  method: 'GET',
  integrationType: 'restApi',
  outputSchemas: {
    [HttpStatusCodes.OK]: {},
  },
  queryStringParametersSchema,
});

export const updateTrainStatusContract = new ApiGatewayContract({
  id: 'put-train-status',
  path: '/trainStatus',
  method: 'PUT',
  integrationType: 'restApi',
  outputSchemas: {
    [HttpStatusCodes.OK]: {},
  },
  queryStringParametersSchema,
});
```

Retrieve documentation
```typescript
const apiDocs = getOpenApiDocumentation({
  title: 'Trains',
  description: 'Trains open api doc',
  contracts: [getTrainStatusContract, updateTrainStatusContract],
});

fs.writeFile('api-doc.json', JSON.stringify(apiDocs, null, 2), 'utf8', () =>
  console.log('file-write'),
);
```

Result:
```json
{
  "openapi": "3.0.1",
  "info": {
    "title": "Trains",
    "description": "Trains open api doc",
    "version": "2023-05-31T13:29:07.404Z"
  },
  "paths": {
    "/trainStatus": {
      "put": {
        "responses": {
          "200": {
            "description": "Response: 200",
            "content": {
              "application/json": {
                "schema": {}
              }
            }
          }
        }
      }
    }
  }
}
```

### System Info

```shell
System:
    OS: macOS 13.4
    CPU: (8) arm64 Apple M1
    Memory: 67.69 MB / 16.00 GB
    Shell: 5.9 - /bin/zsh
  Binaries:
    Node: 18.12.1 - ~/.nvm/versions/node/v18.12.1/bin/node
    Yarn: 1.22.19 - ~/.nvm/versions/node/v18.12.1/bin/yarn
    npm: 8.19.2 - ~/.nvm/versions/node/v18.12.1/bin/npm
  Browsers:
    Chrome: 114.0.5735.90
    Firefox: 113.0.2
    Safari: 16.5
  npmPackages:
    @swarmion/nx-plugin: ^0.28.1 => 0.28.1
    @swarmion/serverless-contracts: ^0.28.1 => 0.28.1
```


### Validations

- [X] Read the [Contributing Guidelines](https://github.com/swarmion/swarmion/blob/main/CONTRIBUTING.md).
- [X] Read the [docs](https://www.swarmion.dev/docs/).
- [X] Check that there isn't [already an issue](https://github.com/swarmion/swarmion/issues) that reports the same bug to avoid creating a duplicate.
- [X] The provided reproduction is a [minimal reproducible example](https://stackoverflow.com/help/minimal-reproducible-example) of the bug.
