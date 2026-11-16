securitySchemes with open api
## Sorting

* **I'm submitting a ...**
  - [X] bug report
  - [ ] feature request
  - [ ] support request

* I confirm that I
  - [X] used the [search](https://github.com/lukeautry/tsoa/search?type=Issues) to make sure that a similar issue hasn't already been submit

## Overview
specyfing the securitySchema in tsoa.json does not produce the correct open api definition in the yaml file.

e.g.
```json
"securityDefinitions": {
			"TEST": {
				"type": "oauth2",
				"flow": "application",
				"tokenUrl": "/ats-api/auth/token",
				"scopes": []
			}
		},
```

produces:
```yaml
securitySchemes:
        TEST:
            type: oauth2
            flow: application
            tokenUrl: /ats-api/auth/token
            scopes: []
```

but should generate:
```yaml
securitySchemes:
       TEST:
            type: oauth2
            flows:
                clientCredentials:
                    tokenUrl: /ats-api/auth/token
            scopes: []
```

see also https://swagger.io/docs/specification/authentication/oauth2/
besides that the wording/flow differences between v2/v3 need either to be documented or considered for next major release to be changed. e.g:
* flow accessCode -> authorizationCode – Authorization Code flow (previously called accessCode in OpenAPI 2.0)
* flow application -> clientCredentials – Client Credentials flow (previously called application in OpenAPI 2.0)

## Expected Behavior
tsoa should generate valid yaml files out of the defined securityDefinition also for v3 / open api.

## Possible Solution
Abstact the security definition so that it can be used for v2 and v3 in a general way.

## Steps to Reproduce
1. create tsoa file with security definition flow application
2. generate open api doc
3. validate security schema

## Context (Environment)
Version of the library: 2.5.8
Version of NodeJS: v12.13.0

### Additional contract requirements

- For OpenAPI 3 OAuth2 definitions, serialize a configured `password` flow under `flows.password`, retaining its token URL and scopes in that flow.
- For OpenAPI 3 OAuth2 definitions, serialize a configured `implicit` flow under `flows.implicit`, retaining its authorization URL and scopes in that flow.
