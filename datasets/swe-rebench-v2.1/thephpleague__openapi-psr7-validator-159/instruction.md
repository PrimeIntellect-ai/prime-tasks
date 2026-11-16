Support Pattern Response Status Codes (2XX, 3XX, 4XX, and 5XX)
According to Open Api Specification 3.0.0 and above
the Response Object alows to describe Error Responses in
https://spec.openapis.org/oas/v3.0.0.html#patterned-fields-0

but the validation currently fails for schemas describing Status ranges.

### Additional contract requirements

- `League\OpenAPIValidation\PSR7\SpecFinder::findResponseSpec(ResponseAddress $address)` returns the response definition for the given address.
- `League\OpenAPIValidation\PSR7\ResponseAddress::__construct(string $path, string $method, int $statusCode)` creates the address used to look up a response definition.
- An exact response code takes precedence over a patterned range (`2XX`, `3XX`, `4XX`, `5XX`), which takes precedence over the `default` response.
