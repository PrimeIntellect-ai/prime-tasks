Parser is not resolving the requestBody to make it inline as its doing for responses
**MetaData** :
- Swagger Parser Version : 2.0.31
- OAS Version: 3.0.0
- Simple Reproducible Spec is pasted at the end

**Reproducible Code Snippet** :
```
io.swagger.v3.parser.core.models.ParseOptions parseOptions = new io.swagger.v3.parser.core.models.ParseOptions();
parseOptions.setResolve(true);
parseOptions.setFlatten(true);
SwaggerParseResult result = new OpenAPIParser().readLocation("<PATH TO SPEC>\\OAS3_Inline_Request_Response_Usecase.json", null, parseOptions);
```

**Context** :
We're using the above snippet for the following reasons and explanation against it -
1. resolve is true: We have usecases where there are external json references and resolve is best fit for us to solve the problem of localizing the external references.
2. flatten is true: We have some usecases that have inline schema definitions for requestBody and responses in an operation. And we need to make them ref locally from components section. And for this flatten is the best fit.

**Issue and Observations** :
- We basically were using the spec below expecting Swagger Parser to flatten up the inline schemas for my referenced requestBody and response, and  then make them refer from components section.
- We observed that the SwaggerParser works fine for responses in flattening up but NOT for requestBody.
- We debugged the flatten implementation, and was shocked that it only fattens the _path inline_ schemas and the schemas under _components/schema_ section, then how is it working for responses.
- We then suspected that there's something in the _resolve_ implementation that is making responses work.
- And bingo, we found it was the exact case and [HIDDEN] the link pointing to that code. I dug deep to find the commit and here it is --> [HIDDEN]
- So its not doing the same for request.
- Hey @gracekarina, I also have a fix for the same, its on the similar lines as its done for responses, I'll raise the PR soon.

**Impact and why we can't use ResolveFully** :
- This very crucial for our Q2 roadmap items.
- We are not able to resolve the inline schemas for the referenced requestBody from components section.
- We can't use resolveFully because it will make everything inline and then we intend to flatten every inline thing, which will rename the older models local references that were not inline, to the newer flattened up naming local reference. I am afraid that using resolveFully and then flatten will lead us to some regressions in our product. Making use of resolve and flatten is the best combination for us, or rather the correct one as we don't wan't to unnecessarily over process using resolveFully.
- The sample we've attached is very basic, and we have very complex usecases that have this inline flavour of referenced requestBody.
- Hey @gracekarina, Please request to help merge the similar changes I am raising in the PR for the requestBody.

**OAS3 Spec** :
```
{
	"openapi": "3.0.0",
	"info": {
		"version": "1.0",
		"title": "Resource service",
		"description": "Resource service"
	},
	"servers": [
		{
			"url": "http://localhost:8088/"
		}
	],
	"paths": {
		"/resource": {
			"post": {
				"summary": "postResource",
				"description": "postResource",
				"operationId": "post-resource",
				"parameters": [],
				"requestBody": {
					"$ref": "#/components/requestBodies/ResourceBodyPost"
				},
				"responses": {
					"200": {
						"$ref": "#/components/responses/ResourceSuccessResponse"
					}
				}
			}
		}
	},
	"components": {
		"requestBodies": {
			"ResourceBodyPost": {
				"content": {
					"application/json": {
						"schema": {
							"type": "object",
							"required": [
								"rqname"
							],
							"properties": {
								"rqname": {
									"type": "string"
								},
								"rqnumber": {
									"type": "integer",
									"format": "int32"
								},
								"rqflag": {
									"type": "boolean"
								}
							}
						}
					}
				}
			}
		},
		"responses": {
			"ResourceSuccessResponse": {
				"description": "a Element to be returned",
				"content": {
					"application/json": {
						"schema": {
							"type": "object",
							"required": [
								"rname"
							],
							"properties": {
								"rname": {
									"type": "string"
								},
								"rnumber": {
									"type": "integer",
									"format": "int32"
								},
								"rflag": {
									"type": "boolean"
								}
							}
						}
					}
				}
			}
		},
		"schemas": {}
	}
}
```

### Additional contract requirements

- `io.swagger.v3.parser.core.models.ParseOptions` exposes a public method `setResolveRequestBody(boolean resolveRequestBody)` that records whether referenced requestBody objects should be inlined during the normal resolve workflow.
- `io.swagger.v3.parser.core.models.ParseOptions` exposes a public method `isResolveRequestBody()` that returns the current value of that flag. It returns `false` unless `setResolveRequestBody(true)` has been called.
- When `setResolveRequestBody(true)` is set together with `setResolve(true)`, a requestBody that is a local `$ref` to `components/requestBodies` is inlined in the operation: its `$ref` becomes null and its content and schema are available directly on the operation's requestBody, matching the existing behaviour for referenced responses.
- The same requestBody inlining applies when both `setResolve(true)` and `setFlatten(true)` are enabled, as in the reported usage.
- When the flag is not set, existing behaviour is preserved: resolve alone does not inline referenced requestBody objects.
