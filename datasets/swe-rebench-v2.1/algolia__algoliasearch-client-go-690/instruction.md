bug(suggestions): deserialization failed when languages are not set
- Algolia Client Version: master(`v3.19.1-0.20210628231352-f4915f52041a`)
- Language Version: 1.16

### Description
JSON deserialization failed by the wrong value type of `"languages":false` when we get the query suggestions config whose `languages` is not set as following.
Expected behaivour is that the suggestions API returns a json with `"languages": null`. (So this issue is not about client library but API)
https://www.algolia.com/doc/rest-api/query-suggestions/#method-param-languages

```
Error: cannot deserialize response's body: json: cannot unmarshal bool into Go struct field IndexConfiguration.languages of type []string:
{
  "appID": "XXXXXXXX",
  "sourceIndicesAPIKey": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "externalIndicesAPIKey": "",
  "suggestionIndicesAPIKey": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "indexName": "test",
  "sourceIndices": [
    {
      "indexName": "test_source",
      "replicas": false,
      "analyticsTags": null,
      "facets": null,
      "minHits": 5,
      "minLetters": 4,
      "generate": null,
      "external": null
    }
  ],
  "languages": false,
  "exclude": null,
  "enablePersonalization": false
}
```

### Steps To Reproduce
1. Create query suggestions index config without setting `languages`.
2. Get the created suggestions index config.
```
package main

import (
	"github.com/algolia/algoliasearch-client-go/v3/algolia/search"
	"github.com/algolia/algoliasearch-client-go/v3/algolia/suggestions"
)

func main() {
	appID := "XXXXXXXXXX"
	apiKey := "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

	searchConfig := search.Configuration{
		AppID:  appID,
		APIKey: apiKey,
	}
	searchClient := search.NewClientWithConfig(searchConfig)
	createIndex(searchClient, "test")
	createIndex(searchClient, "test_source")

	suggestionsConfig := suggestions.Configuration{
		AppID:  appID,
		APIKey: apiKey,
	}
	suggestionsClient := suggestions.NewClientWithConfig(suggestionsConfig)
	err := suggestionsClient.CreateConfig(suggestions.IndexConfiguration{
		IndexName: "test",
		SourceIndices: []suggestions.SourceIndex{
			{IndexName: "test_source"},
		},
	})
	if err != nil {
		panic(err)
	}

	_, err = suggestionsClient.GetConfig("test")
	if err != nil {
		panic(err)
	}
}

func createIndex(searchClient *search.Client, indexName string) {
	res, err := searchClient.InitIndex(indexName).SetSettings(search.Settings{})
	if err != nil {
		panic(err)
	}
	if err := res.Wait(); err != nil {
		panic(err)
	}
}
```

### Additional contract requirements

The client must successfully deserialize the reproduced suggestions configuration when its `languages` value is the boolean `false`. Existing `languages` values represented as arrays of strings must continue to deserialize with their language codes preserved.
