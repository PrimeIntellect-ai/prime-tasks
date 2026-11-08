bug: Generated service_interceptors.go file does not import package for Attributes in ReadPayload with Meta("struct:pkg:path")
When defining a service interceptor with a ReadPayload that includes a type with the Meta("struct:pkg:path"), the generated service_interceptors.go file does not import that package. This results in a compile error in the output codegen when referencing that type. I am using goa v3.20.0.

Minimal example:
```
var _ = Service("example", func() {
	ServerInterceptor(ResourceID)

	Method("get", func() {
		Payload(func() {
			Attribute("id", String)
			Attribute("tenantID", TenantID)
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
		Attribute("tenantID", TenantID)
	})
})

var TenantID = Type("TenantID", String, func() {
	Meta("struct:pkg:path", "ids")
})
```

service_interceptors.go that does not have the needed import:
```
package example

import (
	"context"

	goa "goa.design/goa/v3/pkg"
)

...

	// TenantIDPayload provides type-safe access to the method payload.
	// It allows reading and writing specific fields of the payload as defined
	// in the design.
	TenantIDPayload interface {
		TenantID() TenantID
	}
)
```

service.go that does have the needed import:
```
service.go:

package example

import (
	"context"

	ids "goa.design/examples/basic/gen/ids"
)

...

// GetPayload is the payload type of the example service get method.
type GetPayload struct {
	ID       string
	TenantID ids.TenantID
}
```

Expected behavior: service_interceptors.go imports the ids package and uses it when referencing the TenantID type.
