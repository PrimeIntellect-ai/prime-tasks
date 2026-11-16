Omitting the host property should make the host relative
<!--- Provide a general summary of the issue in the Title above -->
This is the v3 version for the compromise we made in https://github.com/lukeautry/tsoa/pull/547

## Sorting

* **I'm submitting a ...**
  - [ ] bug report
  - [X] feature request
  - [ ] support request

* I confirm that I
  - [X] used the [search](https://github.com/lukeautry/tsoa/search?type=Issues) to make sure that a similar issue hasn't already been submit

## Expected Behavior
<!--- Tell us what should happen -->
<!--- If this is related to swagger/OpenAPI files, then please include swagger.yaml that you wish tsoa had generated  -->
Assuming that the `host` property was not provided and the `basePath` is "v1" (correct me on this if I'm wrong @Eoksni / @jreusch-barco) but the desired output would be:
```yaml
"servers": [
		{
			"url": "/v1"
		}
	]
```
I'd like to be able to specify relative host, which is allowed by specification https://github.com/OAI/OpenAPI-Specification/blob/master/versions/3.0.0.md#fixed-fields-4.

## Current Behavior
Currently if I omit host field in the swagger config or use empty "host": "", it gets replaced with http://localhost:3000. Using "host": "/" also doesn't work.

## Possible Solution
The solutions were discussed in the v2 version of this change: https://github.com/lukeautry/tsoa/issues/540

## Detailed Description
<!--- Provide a detailed description of the change or addition you are proposing -->
We will accept that if someone doesn't specify a host, then it should not default (since tsoa couldn't possibly know which host to default to). It should be relative.

## Breaking change?
<!--- if this is a breaking change, then please describe how it breaks the existing libraries inputs/outputs -->
<!--- if this is a breaking change, then discuss how we can mitigate that -->
Yes, this should be part of the v3 branch.
