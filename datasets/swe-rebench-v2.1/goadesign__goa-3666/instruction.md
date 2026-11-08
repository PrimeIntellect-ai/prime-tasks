bug: Interceptor ReadPayload attributes can't find attributes defined using Extend()
Interceptors seem neat! I tried one out and ran into this issue where ReadPayload attributes can't find attributes defined using Extend(). If I replace the `Extend` with the attribute definition ex: `Attribute("tenantID", String, "Tenant ID for the request")`, the generation works as expected.

Minimal example below:

```
var _ = Service("example", func() {
	ServerInterceptor(ResourceID)

	Method("get", func() {
		Payload(func() {
			Extend(CommonAttributes)
			Attribute("id", String)
			Required("tenantID", "id")
		})

		Result(Int)

		HTTP(func() {
			GET("{tenantID}/resource/{id}")
			Response(StatusOK)
		})
	})
})

var ResourceID = Interceptor("TenantID", func() {
	ReadPayload(func() {
		Attribute("tenantID", String, "Tenant ID for request")
	})
})

var CommonAttributes = Type("Common", func() {
	Attribute("tenantID", String, "Tenant ID for the request")
})
```

`gen` output:
`service "example" method "get": interceptor "TenantID" cannot read payload attribute "tenantID": attribute does not exist`

Expected:
The server interceptor can find all of the attributes, including those that are defined using Extend.
