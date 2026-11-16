UpdateService is not working properly with AlertGroupingParameters
If a PD service has data inside svc.AlerGroupingParameters.Config.Timeout it doesn't appear to be correctly sent when updating, for example if there was an indefinite time-based alert grouping configured.

POC:
```go
package main

import (
	"context"
	"fmt"
	"github.com/PagerDuty/go-pagerduty"
)

var (
	authToken = "<REDACTED>"
	serviceId = "<REDACTED>"
)

func main() {
	client := pagerduty.NewClient(authToken)
	svc, err := client.GetServiceWithContext(context.TODO(), serviceId, nil)
	if err != nil {
		panic(err)
	}

       // If the service has data inside svc.AlertGroupingParameters.Config.Timeout it doesn't appear to be respected, e.g.
       // if there was an indefinite time-based alert grouping configured.
       // pagerduty.AlertGroupingParameters{Type:"time", Config:(*pagerduty.AlertGroupParamsConfig)(0x140001810e0)}
       // pagerduty.AlertGroupParamsConfig{Timeout:0x0, Aggregate:"", Fields:[]string(nil)}

	_, err = client.UpdateServiceWithContext(context.TODO(), *svc)
	if err != nil {
		// Results in panic: HTTP response failed with status code 400,
		// message: Invalid Input Provided (code: 2001): Config is invalid.
		panic(err)
	}
}
```

### Additional contract requirements

Updating a service must send its configured alert-grouping timeout, including an explicit zero for indefinite time-based grouping.
