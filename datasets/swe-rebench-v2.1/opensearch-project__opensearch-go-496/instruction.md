[BUG] Invalid Sigv4 on requests without a body using AWS SDK v1
### What is the bug?
Getting Error: status: [403 Forbidden] exit status 1 when connecting to OpenSearch using AWS SDK v1

### How can one reproduce the bug?
The following code gives Error: status: [403 Forbidden]
exit status 1

```
package main

import (
	"context"
	"fmt"
	"os"

	"github.com/aws/aws-sdk-go/aws/session"
	requestsigner "github.com/opensearch-project/opensearch-go/v3/signer/aws"

	"github.com/opensearch-project/opensearch-go/v3"
	"github.com/opensearch-project/opensearch-go/v3/opensearchapi"
)

const IndexName = "go-test-index1"

func main() {
	if err := example(); err != nil {
		fmt.Println(fmt.Sprintf("Error: %s", err))
		os.Exit(1)
	}
}

const endpoint = "endpoint url" // e.g. https://opensearch-domain.region.com

func example() error {
	// Create an AWS request Signer and load AWS configuration using default config folder or env vars.
	// See https://docs.aws.amazon.com/opensearch-service/latest/developerguide/request-signing.html#request-signing-go
	signer, err := requestsigner.NewSignerWithService(
		session.Options{Profile: "default"},
		requestsigner.OpenSearchService, // Use requestsigner.OpenSearchServerless for Amazon OpenSearch Serverless.
	)
	if err != nil {
		return err
	}
	// Create an opensearch client and use the request-signer.
	client, err := opensearchapi.NewClient(
		opensearchapi.Config{
			Client: opensearch.Config{
				Addresses: []string{endpoint},
				Signer:    signer,
			},
		},
	)
	if err != nil {
		return err
	}

	ctx := context.Background()

	ping, err := client.Ping(ctx, nil)
	if err != nil {
		return err
	}

	fmt.Println(ping)

	return nil
}

```

### What is the expected behavior?
Connection should be successful

### What is your host/environment?
Distributor ID: Debian
Description:    Debian GNU/Linux 11 (bullseye)
Release:        11
Codename:       bullseye


### Do you have any screenshots?
![golangawssdkopensearch](https://github.com/opensearch-project/opensearch-go/assets/35212670/eb927f90-9a9b-4df8-9c1c-ca44ca5ac41c)


### Do you have any additional context?
I am able to connect using AWS SDK v1 with the same credentials.
