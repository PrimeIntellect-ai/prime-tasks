Improve the error message when adding documents
Currently, when adding json documents to meilisearch, you can either add them as a single document;
```bash
curl -X POST 'http://localhost:7700/indexes/mieli/documents'  -H 'Content-type: application/json' -d '{ "id": 1, "pet": "dog" }'
```
Or as an array of documents;
```bash
curl -X POST 'http://localhost:7700/indexes/mieli/documents'  -H 'Content-type: application/json' -d '[{ "id": 1, "pet": "dog" }, { "id": 2, "pet": "doggo" }]'
```

That's cool, but the error messages are not explicit at all;
```bash
curl -X POST 'http://localhost:7700/indexes/mieli/documents'  -H 'Content-type: application/json' -d '"sending a string instead of a json"'
```
For example, with this request we get this error message;
```
The `json` payload provided is malformed. `Couldn't serialize document value: data did not match any variant of untagged enum Either`.
```

I would like to improve this message and get rids entirely of the notion of « untagget enum » and « Either ».

### Additional contract requirements

- When a JSON document-addition payload is neither an object nor a list of objects, the error message must be exactly: `The `json` payload provided is malformed. `Couldn't serialize document value: data are neither an object nor a list of objects`.`
