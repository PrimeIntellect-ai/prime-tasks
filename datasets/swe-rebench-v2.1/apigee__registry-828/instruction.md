Registry Tool: bulk upload commands don't validate project ID flag
Running the bulk upload commands without specifying a project ID will proceed without error until it attempts to use the project ID in a request to the server. Failing to specify the project ID should immediately fail with an informative error message.

```
$ registry upload bulk openapi ~/Desktop/openapi-directory
  INFO[0000] Uploading apis/apis-1forge.com/versions/0.0.1/specs/swagger.yaml uid=7aa38e1e
 DEBUG[0000] Failed to create API projects//locations/global/apis/apis-1forge.com error=rpc error: code = InvalidArgument desc = invalid API name "projects//locations/global/apis/apis-1forge.com": must match "^projects/([A-Za-z0-9-.]+)/locations/global/apis/([A-Za-z0-9-.]+)$" uid=7aa38e1e
```

```
$ registry upload bulk protos ~/Desktop/googleapis/
  INFO[0000] Uploading apis/actions/versions/v2/specs/google-actions-sdk-v2.zip uid=7c0971c6
 DEBUG[0000] Failed to create API projects//locations/global/apis/actions error=rpc error: code = InvalidArgument desc = invalid API name "projects//locations/global/apis/actions": must match "^projects/([A-Za-z0-9-.]+)/locations/global/apis/([A-Za-z0-9-.]+)$" uid=7c0971c6
```
