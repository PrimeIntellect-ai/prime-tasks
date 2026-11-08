Support for relative `host` in openapi 3
<!--- Provide a general summary of the issue in the Title above -->

## Sorting

* **I'm submitting a ...**
  - [ ] bug report
  - [x] feature request
  - [ ] support request

* I confirm that I
  - [x] used the [search](https://github.com/lukeautry/tsoa/search?type=Issues) to make sure that a similar issue hasn't already been submit

## Expected Behavior

Have in the output something like
```json
	"servers": [
		{
			"url": "/v1"
		}
	]
```

I'd like to be able to specify relative `host`, which is allowed by specification https://github.com/OAI/OpenAPI-Specification/blob/master/versions/3.0.0.md#fixed-fields-4.

## Current Behavior
Currently if I omit `host` field in the `swagger` config or use empty `"host": ""`, it gets replaced with `http://localhost:3000`. Using `"host": "/"` also doesn't work.

## Possible Solution

## Steps to Reproduce

## Context (Environment)
Version of the library: 2.5.9
Version of NodeJS: 12
* Confirm you were using yarn not npm: [ ]

## Detailed Description

## Breaking change?

### Additional contract requirements

When the OpenAPI 3 configuration sets `host` to `null`, the generated server URL must be relative and use the configured base path (for example, `/v1`) instead of defaulting to an absolute localhost URL.
