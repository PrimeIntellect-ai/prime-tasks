query param with anyOf failed to parse
query param with anyOf failed to parse

Openapi yaml with:

paths:
/resource-store:
get:
operationId: SearchResources
tags:
- Resource Store)
parameters:
- name: resource-type
in: query
description: Type of the resource to get
required: true
schema:
$ref: '#/components/schemas/RESOURCEType'
responses:
xxxx

components:
schemas:
RESOURCEType:
anyOf:
- type: string
enum:
- MEM
- CPU
- DISK
- type: string

====
when I succeeded to build and run the server, it panics at requests with this message:
echo: http: panic serving [::1]:56426: schema has non primitive type ""
goroutine 12 [running]:
net/http.(*conn).serve.func1(0xc000088140)
/usr/local/go/src/net/http/server.go:1769 +0x139
panic(0x86c960, 0xc0004740a0)
/usr/local/go/src/runtime/panic.go:522 +0x1b5
github.com/getkin/kin-openapi/openapi3filter.parsePrimitive(0xc00002c6e0, 0x3, 0xc00022cd00, 0x23, 0xc00005b7b8, 0x3, 0x3)
/home/admin/go/src/github.com/getkin/kin-openapi/openapi3filter/req_resp_decoder.go:705 +0xa1e
github.com/getkin/kin-openapi/openapi3filter.(*urlValuesDecoder).DecodePrimitive(0xc000010040, 0xc000161fe0, 0xd, 0xc000466080, 0xc00022cd00, 0x8, 0xc000010040, 0x5, 0x0)
/home/admin/go/src/github.com/getkin/kin-openapi/openapi3filter/req_resp_decoder.go:412 +0x329
github.com/getkin/kin-openapi/openapi3filter.decodeValue(0x9c6ba0, 0xc000010040, 0xc000161fe0, 0xd, 0xc000466080, 0xc00022cd00, 0x0, 0x0, 0x0, 0x0)
/home/admin/go/src/github.com/getkin/kin-openapi/openapi3filter/req_resp_decoder.go:243 +0xcf
github.com/getkin/kin-openapi/openapi3filter.decodeStyledParameter(0xc0000e0500, 0xc00045c450, 0x0, 0x0, 0x0, 0x0)
/home/admin/go/src/github.com/getkin/kin-openapi/openapi3filter/req_resp_decoder.go:225 +0x134
github.com/getkin/kin-openapi/openapi3filter.ValidateParameter(0x9c7f20, 0xc00045c4b0, 0xc00045c450, 0xc0000e0500, 0x0, 0x0)
/home/admin/go/src/github.com/getkin/kin-openapi/openapi3filter/validate_request.go:95 +0x350
github.com/getkin/kin-openapi/openapi3filter.ValidateRequest(0x9c7f20, 0xc00045c4b0, 0xc00045c450, 0x9b4cf0, 0x9117e0)
/home/admin/go/src/github.com/getkin/kin-openapi/openapi3filter/validate_request.go:49 +0x243
github.com/deepmap/oapi-codegen/pkg/middleware.ValidateRequestFromContext(0x9d4600, 0xc0000de5a0, 0xc000142b60, 0x0, 0x5d259d4c, 0xb0915dc)
/home/admin/go/src/github.com/deepmap/oapi-codegen/pkg/middleware/oapi_validate.go:115 +0x537
github.com/deepmap/oapi-codegen/pkg/middleware.OapiRequestValidatorWithOptions.func1.1(0x9d4600, 0xc0000de5a0, 0xd09620, 0xc00005bc28)
/home/admin/go/src/github.com/deepmap/oapi-codegen/pkg/middleware/oapi_validate.go:69 +0x54
github.com/labstack/echo/middleware.LoggerWithConfig.func2.1(0x9d4600, 0xc0000de5a0, 0x2, 0x2)
/home/admin/go/src/github.com/labstack/echo/middleware/logger.go:119 +0x1c0
github.com/labstack/echo.(*Echo).ServeHTTP(0xc000224380, 0x9c6fa0, 0xc0000c6000, 0xc0000e8000)
/home/admin/go/src/github.com/labstack/echo/echo.go:616 +0x22d
net/http.serverHandler.ServeHTTP(0xc00014a9c0, 0x9c6fa0, 0xc0000c6000, 0xc0000e8000)
/usr/local/go/src/net/http/server.go:2774 +0xa8
net/http.(*conn).serve(0xc000088140, 0x9c7e60, 0xc000458840)

The request is:
curl "localhost:8080/resource-store?resource-type=CPU"

I solved the issue by simply declaring:
RESOURCEType:
type: string

Still, I'd like to understand the cause behind the former syntax and the possibility to get the former syntax work.

Thanks,
Charlie
