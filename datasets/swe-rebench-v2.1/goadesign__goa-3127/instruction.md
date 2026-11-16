HTTP clients don't generate correctly when using a CommonType
When we generate our HTTP client from a design that uses a `CommonType`, the http `types.go` files still looks in the specific service package, instead of common.

e.g.
```
// NewBuildApplicableFieldsResponseBody builds the HTTP response body from the
// result of the "BuildApplicableFields" endpoint of the "Incidents" service.
func NewBuildApplicableFieldsResponseBody(res *incidents.IncidentApplicableFields) *BuildApplicableFieldsResponseBody {
	body := &BuildApplicableFieldsResponseBody{}
	return body
}
```

Should be
```
// NewBuildApplicableFieldsResponseBody builds the HTTP response body from the
// result of the "BuildApplicableFields" endpoint of the "Incidents" service.
func NewBuildApplicableFieldsResponseBody(res *common.IncidentApplicableFields) *BuildApplicableFieldsResponseBody {
	body := &BuildApplicableFieldsResponseBody{}
	return body
}
```
