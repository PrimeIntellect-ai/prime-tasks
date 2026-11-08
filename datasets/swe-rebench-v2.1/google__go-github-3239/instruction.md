ProvisionAndInviteSCIMUser query instead body
Hello,

I encountered an issue with the wrong construction of a request to the GitHub SCIM API. I tried to use the function `ProvisionAndInviteSCIMUser`, but according to the [GitHub documentation](https://docs.github.com/en/enterprise-cloud@latest/rest/scim/scim?apiVersion=2022-11-28#provision-and-invite-a-scim-user), user data must be passed to the API in the body of the request. Unfortunately, the library `go-github` sends `SCIMUserAttributes` as query parameters.

Here is en example of the code:
```
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http/httputil"

	"github.com/google/go-github/v63/github"
)

var gh_pers_token string = "github_pat_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
var github_org string = "example"

func main() {
	fmt.Println("Create test users on GitHub")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	opts := &github.SCIMUserAttributes{
		UserName: "userName",
		Name: github.SCIMUserName{
			GivenName:  "givenName",
			FamilyName: "familyName",
		},
		Emails: []*github.SCIMUserEmail{
			{
				Value: "octocat@github.com",
			},
		},
	}

	fmt.Println("The opts are: ", opts)
	show_data, _ := json.MarshalIndent(opts, "", "\t")
	fmt.Println("Show opts:", string(show_data))

	client := github.NewClient(nil).WithAuthToken(gh_pers_token)

	// Create users
	res, err := client.SCIM.ProvisionAndInviteSCIMUser(ctx, github_org, opts)
	if err != nil {
		fmt.Println("The response is: ", res)
		defer res.Body.Close()

		b, error := httputil.DumpResponse(res.Response, true)
		if error != nil {
			fmt.Println(error)
		}

		fmt.Println(string(b))
		fmt.Println(err)
	}
}
```

And here is the output:
```
% go run main.go
Create test users on GitHub
The opts are:  &{userName {givenName familyName <nil>} <nil> [0xc000074160] [] <nil> [] <nil> <nil> <nil>}
Show opts: {
        "userName": "userName",
        "name": {
                "givenName": "givenName",
                "familyName": "familyName"
        },
        "emails": [
                {
                        "value": "octocat@github.com"
                }
        ]
}
The response is:  &{0xc0000d2120 0 0 0 0     github.Rate{Limit:5000, Remaining:4995, Reset:github.Timestamp{2024-08-20 22:40:40 +0500 +05}} 2025-05-07 00:00:00 +0500 +05}
HTTP/2.0 400 Bad Request
Content-Length: 154
Access-Control-Allow-Origin: *
Access-Control-Expose-Headers: ETag, Link, Location, Retry-After, X-GitHub-OTP, X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Used, X-RateLimit-Resource, X-RateLimit-Reset, X-OAuth-Scopes, X-Accepted-OAuth-Scopes, X-Poll-Interval, X-GitHub-Media-Type, X-GitHub-SSO, X-GitHub-Request-Id, Deprecation, Sunset
Content-Security-Policy: default-src 'none'
Content-Type: application/scim+json
Date: Tue, 20 Aug 2024 17:16:03 GMT
Github-Authentication-Token-Expiration: 2025-05-07 00:00:00 +0500
Referrer-Policy: origin-when-cross-origin, strict-origin-when-cross-origin
Server: github.com
Strict-Transport-Security: max-age=31536000; includeSubdomains; preload
Vary: Accept-Encoding, Accept, X-Requested-With
X-Accepted-Github-Permissions: members=write
X-Content-Type-Options: nosniff
X-Frame-Options: deny
X-Github-Api-Version-Selected: 2022-11-28
X-Github-Media-Type: github.v3; format=json
X-Github-Request-Id: C1B6:C1EBC:2532330:258A88B:66C4CF52
X-Ratelimit-Limit: 5000
X-Ratelimit-Remaining: 4995
X-Ratelimit-Reset: 1724175640
X-Ratelimit-Resource: core
X-Ratelimit-Used: 5
X-Xss-Protection: 0

{"schemas":["urn:ietf:params:scim:api:messages:2.0:Error"],"status":400,"scimType":"invalidSyntax","detail":"For 'links/1/schema', nil is not an object."}
POST https://api.github.com/scim/v2/organizations/example/Users?Active=&DisplayName=&Emails=%7Boctocat%40github.com+%3Cnil%3E+%3Cnil%3E%7D&ExternalID=&ID=&Meta=&Name%5BFamilyName%5D=familyName&Name%5BFormatted%5D=&Name%5BGivenName%5D=givenName&UserName=userName: 400  []
```
[HIDDEN]

There is a chance that I have wrongly made conclusions since I am not an expert in Golang. If so, could you please point me in the direction of how the function `ProvisionAndInviteSCIMUser` should be used properly?
Thank you in advance.

### Additional contract requirements

- `SCIMService.ProvisionAndInviteSCIMUser(ctx context.Context, org string, opts *SCIMUserAttributes) (*SCIMUserAttributes, *Response, error)` is a public method in package `github`. It sends the SCIM user data as a JSON request body in a POST request to the organization's SCIM Users endpoint, and returns the created user populated with the fields returned by the API (for example `ID` and `UserName`), together with the HTTP response.
