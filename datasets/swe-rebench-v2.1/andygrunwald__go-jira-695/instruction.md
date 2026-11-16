Adding comments to issues won't work
The reason is that the when serializing the body as json some extra is sent because the omitempty doesn't work as expected.

see this example: https://go.dev/play/p/7DCOpLbUdq4

this will cause the request to send `visibility: {}` which is rejected by the Jira API, the same happens with Author and UpdateAuthor properties.

[HIDDEN]

```go
// Comment represents a comment by a person to an issue in Jira.
type Comment struct {
	ID           string             `json:"id,omitempty" structs:"id,omitempty"`
	Self         string             `json:"self,omitempty" structs:"self,omitempty"`
	Name         string             `json:"name,omitempty" structs:"name,omitempty"`
	[HIDDEN]
	Body         string             `json:"body,omitempty" structs:"body,omitempty"`
	[HIDDEN]
	Updated      string             `json:"updated,omitempty" structs:"updated,omitempty"`
	Created      string             `json:"created,omitempty" structs:"created,omitempty"`
	[HIDDEN]

	// A list of comment properties. Optional on create and update.
	Properties []EntityProperty `json:"properties,omitempty" structs:"properties,omitempty"`
}
```

this is tested and works as expected

### Additional contract requirements

- When visibility, author, or update-author data is absent, serializing a comment must omit that data rather than send it as an empty object.
- When provided, visibility, author, and update-author data must remain available in the serialized comment.
