`missing_master_key` error
**Describe the bug**
Based on the [spec](https://github.com/meilisearch/specifications/pull/179/files), the user user gets this error when they try accessing the `/keys` route without setting the master key.
I didn’t set a master key:
- If I try accessing the keys route without the authorization header, I get  `missing_master_key`
- If I try accessing the keys route with a non-existent key, I get `invalid_api_key`

Shouldn’t I get  `missing_master_key` in both cases because I didn’t set the master key?

**To Reproduce**
Steps to reproduce the behavior:
1. Launch Meilisearch without a master key
2. Access a keys endpoint without the authorization header, e.g.
``` curl \
  -X GET 'http://localhost:7700/keys?limit=3' \
  ```
  Error message:
  ```
  {"message":"Meilisearch is running without a master key. To access this API endpoint, you must have set a master key at launch.",
"code":"missing_master_key",
"type":"auth",
"link":"https://docs.meilisearch.com/errors#missing_master_key"}
```
3. Access the same route with a non-existent master key:
```
 curl \
  -X GET 'http://localhost:7700/keys?limit=3' \
  -H 'Authorization: Bearer MASTER_KEY'
```
Error message:
```
{"message":"The provided API key is invalid.",
"code":"invalid_api_key",
"type":"auth",
"link":"https://docs.meilisearch.com/errors#invalid_api_key"}
```

**Expected behavior**
 I should get  `missing_master_key` in both cases because I didn’t set the master key


**Meilisearch version:** v0.30rc4

### Additional contract requirements

- When no master key is configured and a nonexistent key is supplied to a keys endpoint, the response must have HTTP status 401.
