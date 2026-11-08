Validate missing '{' in baseUri
Parsing the following raml:
```yaml
#%RAML 1.0
title: Test
baseUri: http://{myapi.com
```

Actual result:
RAML is parsed

Output:
{
    "title": {
        "value": "Test"
    },
    "baseUri": {
        "value": "http://{myapi.com"
    }
}

Expected result:
Parser should validate missing '{'

### Additional contract requirements

- A `baseUri` containing unpaired URI template braces must be reported as a validation error. This includes an opening `{` with no matching `}` (for example `baseUri: http://{myapi.com`) and a closing `}` with no matching `{` (for example `baseUri: http://myapi}.com`).
- A `baseUri` whose URI template parameters are balanced (for example `baseUri: https://{bucketName}.s3.amazonaws.com`) must remain valid.
