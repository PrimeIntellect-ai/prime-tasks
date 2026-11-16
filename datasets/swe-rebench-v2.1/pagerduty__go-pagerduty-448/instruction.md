Chaining GetService and UpdateService fails when AlertGroupingParameters is omitted
```go
service, err := pd.GetService(serviceID, nil)
if err != nil {
    return err
}

service.status = "disabled"

if _, err = pd.UpdateService(*service); err != nil {
    return err
}
```

Results in the following when the following error when `AlertGroupingParameters` is unset/omitted by Go:
```
"error":"HTTP response failed with status code 400, message: Invalid Input Provided (code: 2001): Alert grouping parameters is invalid."
```

The JSON response from GetService looks like:
```json
"alert_grouping_parameters": {
      "type": null,
      "config": null
    },
```

but the resulting struct ends up like, which the PagerDuty API doesn't seem to like:
```go
pd.AlertGroupingParameters{
	Type:   "",
	Config: pd.AlertGroupParamsConfig{
		Timeout:   0,
		Aggregate: "",
		Fields:    nil,
	},
}
```
