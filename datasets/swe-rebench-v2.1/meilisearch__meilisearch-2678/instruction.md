can't index a single json
**Describe the bug**
When I try to send a json document to meilisearch it doesn’t works

**To Reproduce**
Steps to reproduce the behavior:
1. Send a json document to meilisearch: `echo '{ "id": 1 }' | mieli d a`
2.
```json
  {
    "code": "malformed_payload",
    "link": "https://docs.meilisearch.com/errors#malformed_payload",
    "message": "The `json` payload provided is malformed. `Couldn't serialize document value: invalid type: map, expected a sequence at line 1 column 1`.",
    "type": "invalid_request"
  }
  ```

**Expected behavior**
It works.

**Screenshots**
<img width="1244" alt="image" src="https://user-images.githubusercontent.com/7032172/184883362-07768529-f414-481a-94ef-69563d19122b.png">

**Meilisearch version:** main branch

**Additional context**
It's working in the last release.

### Additional contract requirements

- For malformed JSON document payloads, the error message must be exactly: "The `json` payload provided is malformed. `Couldn't serialize document value: data did not match any variant of untagged enum Either`."
