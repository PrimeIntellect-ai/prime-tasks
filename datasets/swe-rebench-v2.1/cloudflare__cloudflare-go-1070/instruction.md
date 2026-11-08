Email Routing Catch All does not match the API docs
### Confirmation

- [X] My issue isn't already found on the issue tracker.
- [X] I have replicated my issue using the latest version of the library and it is still present.

### cloudflare-go version

latest

### Go environment

N/A

### Expected output

Expect an API response of
```json
{
  "tag": "a7e6fb77503c41d8a7f3113c6918f10c",
  "name": "Send to user@example.net rule.",
  "enabled": true,
  "matchers": [
    {
      "type": "all"
    }
  ],
  "actions": [
    {
      "type": "forward",
      "value": [
        "destinationaddress@example.net"
      ]
    }
  ]
}
```

### Actual output

Seeing a response of
```json
{
  "result": {
    "tag": "dd4b8763079149b582cbe76bf86e8910",
    "name": "Send to user@example.net rule.",
    "matchers": [
      {
        "type": "all"
      }
    ],
    "actions": [
      {
        "type": "forward",
        "value": [
          "destinationaddress@example.net"
        ]
      }
    ],
    "enabled": true,
    "priority": 2147483647
  },
  "success": true,
  "errors": [],
  "messages": []
}
```

This causes the return values from both Get and Update to always return an empty `EmailRoutingCatchAllRule`.

### Code demonstrating the issue

```go
package main

import (
	"context"
	"fmt"
	"log"

	"github.com/cloudflare/cloudflare-go"
)

func main() {
	// Construct a new API object using a global API key
	// alternatively, you can use a scoped API token
	api, err := cloudflare.NewWithAPIToken("<API TOKEN>", cloudflare.Debug(true))
	if err != nil {
		log.Fatal(err)
	}

	// Most API calls require a Context
	ctx := context.Background()

	res, err := api.GetEmailRoutingCatchAllRule(ctx, cloudflare.ZoneIdentifier("<ZONE ID>"))
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("%#v", res)
```
```bash
cloudflare-go [DEBUG] REQUEST Method:GET URI:https://api.cloudflare.com/client/v4/zones/<zone id>/email/routing/rules/catch_all Headers:http.Header(nil) Body:<nil>
cloudflare-go [DEBUG] RESPONSE StatusCode:200 RayID:74296582289d3010-BOS ContentType:application/json; charset=UTF-8 Body:"{\"result\":{\"tag\":\"dd4b8763079149b582cbe76bf86e8910\",\"name\":\"\",\"matchers\":[{\"type\":\"all\"}],\"actions\":[{\"type\":\"forward\",\"value\":[\"destinationaddress@example.net\"]}],\"enabled\":true,\"priority\":2147483647},\"success\":true,\"errors\":[],\"messages\":[]}"

{"result":{"tag":"dd4b8763079149b582cbe76bf86e8910","name":"","matchers":[{"type":"all"}],"actions":[{"type":"forward","value":["destinationaddress@example.net"]}],"enabled":true,"priority":2147483647},"success":true,"errors":[],"messages":[]}

cloudflare.EmailRoutingCatchAllRule{Tag:"", Name:"", Enabled:(*bool)(nil), Matchers:[]cloudflare.EmailRoutingRuleMatcher(nil), Actions:[]cloudflare.EmailRoutingRuleAction(nil)}
```

### Steps to reproduce

Run the code given

### References

API Docs Links
https://api.cloudflare.com/#email-routing-routing-rules-get-catch-all-rule
https://api.cloudflare.com/#email-routing-routing-rules-update-catch-all-rule
