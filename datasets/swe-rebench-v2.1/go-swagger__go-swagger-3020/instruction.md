Generate models failed after separate swagger files, maybe caused by a self-ref property of a definition in the separated swagger file
## Problem statement

I have two swagger files: the main file(swagger.yaml, including path-item referencing swagger/business.yaml) and a separated file(swagger/business.yaml) in the subfolder. When I tried to generate models directly using swagger/business.yaml, it succeeded. But when I tried to generate models using swagger.yaml, it ran to a panic error. And it is very weird  that when I comment the last four lines in swagger/buissiness.yaml, it ran to success

## Swagger specification
[test-swagger.zip](https://github.com/go-swagger/go-swagger/files/4896092/test-swagger.zip)
swagger.yaml
```yaml
swagger: "2.0"
info:
  description: "ms api"
  version: "1.0.0"
  title: "ms api"

host: "127.0.0.1:8613"
basePath: "/rest/ms"

tags:
  - name: "business"
    description: "business info"
    externalDocs:
      description: "Find out more"
      url: "http://swagger.io"
schemes:
  - "http"

security:
  - api_key: []

paths:
  /business:
    $ref: "business.yaml#/paths/~1business"

```
swagger/business.yaml
```yaml
swagger: "2.0"
info:
  description: "Business Sub API"
  version: "1.0.0"
  title: "Business Sub-API"

host: "127.0.0.1:8080"
basePath: "/rest/ms"

tags:
  - name: "business"
    description: "business info"
    externalDocs:
      description: "Find out more"
      url: "http://swagger.io"

paths:
  /business:
    post:
      summary: Create a business
      operationId: createBusiness
      tags:
        - "business"
      parameters:
        - name: body
          in: body
          required: true
          schema:
            $ref: '#/definitions/Business'
      responses:
        200:
          description: OK
          schema:
            type: object
definitions:
  Business:
    type: object
    properties:
      children:
        type: array
        x-go-custom-tag: bson:"-"
        items:
          $ref: '#/definitions/Business'
      users:
        type: array
        x-go-custom-tag: bson:"users"
        items:
          type: object
          properties:
            role:
              type: string
              x-go-custom-tag: bson:"role"

```
> I have tried several ways to reproduce the error, such as comment the last four lines(success), change the `children` item $ref to definitions other than `#/definitions/Business`(success), remove the `children` property from Business(success), so I wonder maybe the self-ref `#/definitions/Business` is the key point, but I cant figure out the root cause.
## Steps to reproduce
1. `swagger generate model --with-flatten=expand -f swagger.yaml`
```shell
...
generator:2020/07/09 17:59:36 model.go:701: property createBusinessParamsBody["children"] (tup: false) HasValidations: true)
generator:2020/07/09 17:59:36 types.go:634: resolving schema (anon: true, req: false)
generator:2020/07/09 17:59:36 types.go:346: resolving array (anon: true, req: false)
generator:2020/07/09 17:59:36 types.go:634: resolving schema (anon: true, req: false)
generator:2020/07/09 17:59:36 types.go:230: resolving ref (anon: false, req: false) #/definitions/business
panic: object has no key "business"

goroutine 1 [running]:
github.com/go-openapi/spec.ResolveRef(0x189ba80, 0xc0005cf600, 0xc000de4498, 0x3, 0x3, 0xc001916080)
        /go/pkg/mod/github.com/go-openapi/spec@v0.19.8/expander.go:55 +0x350
github.com/go-swagger/go-swagger/generator.(*typeResolver).resolveSchemaRef(0xc00008ba90, 0xc000de4480, 0x1930a00, 0x6, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, ...)
        /app/generator/types.go:235 +0x190
github.com/go-swagger/go-swagger/generator.(*typeResolver).ResolveSchema(0xc00008ba90, 0xc000de4480, 0xc001910001, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, ...)
        /app/generator/types.go:644 +0x1df
github.com/go-swagger/go-swagger/generator.(*typeResolver).resolveArray(0xc00008ba90, 0xc001917498, 0xc001a60001, 0x100, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, ...)
        /app/generator/types.go:374 +0x1a3
github.com/go-swagger/go-swagger/generator.(*typeResolver).ResolveSchema(0xc00008ba90, 0xc001917498, 0x1, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, ...)
        /app/generator/types.go:680 +0x8e3
github.com/go-swagger/go-swagger/generator.(*schemaGenContext).buildProperties(0xc001aab800, 0x4a, 0xc0019181d8)
        /app/generator/model.go:705 +0x4c3
github.com/go-swagger/go-swagger/generator.(*schemaGenContext).makeGenSchema(0xc001aab800, 0x1, 0x0)
        /app/generator/model.go:1944 +0xc96
github.com/go-swagger/go-swagger/generator.(*codeGenOpBuilder).liftExtraSchemas(0xc00191cfa8, 0xc00008b630, 0xc00008b720, 0xc000e07440, 0xc000cd4600, 0x1fdabbf, 0x18112e0, 0xc000b2e9f0)
        /app/generator/operation.go:1027 +0x1ae
github.com/go-swagger/go-swagger/generator.(*codeGenOpBuilder).buildOperationSchema(0xc00191cfa8, 0xc000d1fbb0, 0x6, 0xc000da00a0, 0x18, 0xc000da0080, 0x12, 0x192bd8c, 0x1, 0x192bd88, ...)
        /app/generator/operation.go:1092 +0x6ac
github.com/go-swagger/go-swagger/generator.(*codeGenOpBuilder).MakeBodyParameter(0xc00191cfa8, 0xc00191a9f8, 0xc00008b630, 0xc001553440, 0x0, 0x0)
        /app/generator/operation.go:773 +0x1f8
github.com/go-swagger/go-swagger/generator.(*codeGenOpBuilder).MakeParameter(0xc00191cfa8, 0x192bd8c, 0x1, 0xc00008b630, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, ...)
        /app/generator/operation.go:735 +0xe55
github.com/go-swagger/go-swagger/generator.(*codeGenOpBuilder).MakeOperation(0xc00191cfa8, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, ...)
        /app/generator/operation.go:325 +0x528
github.com/go-swagger/go-swagger/generator.(*appGenerator).makeCodegenApp(0xc0006a7b00, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, ...)
        /app/generator/support.go:303 +0xfb2
github.com/go-swagger/go-swagger/generator.(*appGenerator).Generate(0xc0006a7b00, 0x0, 0x0)
        /app/generator/support.go:131 +0x7e
github.com/go-swagger/go-swagger/generator.GenerateServer(0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0xc000441d40, 0x0, ...)
        /app/generator/support.go:40 +0xcb
github.com/go-swagger/go-swagger/cmd/swagger/commands/generate.(*Model).generate(0xc00020d7a0, 0xc000441d40, 0x0, 0x0)
        /app/cmd/swagger/commands/generate/model.go:84 +0x124
github.com/go-swagger/go-swagger/cmd/swagger/commands/generate.createSwagger(0x1ac5100, 0xc00020d7a0, 0x185ee80, 0x18927e0)
        /app/cmd/swagger/commands/generate/shared.go:179 +0x225
github.com/go-swagger/go-swagger/cmd/swagger/commands/generate.(*Model).Execute(0xc00020d7a0, 0xc00008a9b0, 0x0, 0x5, 0xc00020d7a0, 0x1)
        /app/cmd/swagger/commands/generate/model.go:97 +0xa1
github.com/jessevdk/go-flags.(*Parser).ParseArgs(0xc00068d620, 0xc000030250, 0x5, 0x5, 0x10, 0x196df08, 0x2a, 0x17ef660, 0xc00036f0e0)
        /go/pkg/mod/github.com/jessevdk/go-flags@v1.4.0/parser.go:316 +0x8c0
github.com/jessevdk/go-flags.(*Parser).Parse(...)
        /go/pkg/mod/github.com/jessevdk/go-flags@v1.4.0/parser.go:186
main.main()
        /app/cmd/swagger/swagger.go:145 +0xafc

```
> I have set DEBUG=1 here
2. `swagger generate model --with-flatten=expand -f swagger/business.yaml`
```shell
2020/07/09 18:02:22 preprocessing spec with option:  expand
2020/07/09 18:02:22 building a plan for generation
2020/07/09 18:02:22 generation target ./
2020/07/09 18:02:22 planning definitions
2020/07/09 18:02:22 planning operations
2020/07/09 18:02:22 grouping operations into packages
2020/07/09 18:02:22 planning meta data and facades
2020/07/09 18:02:22 rendering 1 models
2020/07/09 18:02:22 rendering 1 templates for model Business
2020/07/09 18:02:22 name field Business
2020/07/09 18:02:22 package field models
2020/07/09 18:02:22 creating generated file "business.go" in "models" as definition
2020/07/09 18:02:22 executed template asset:model
2020/07/09 18:02:22 Generation completed!

For this generation to compile you need to have some packages in your GOPATH:

        * github.com/go-openapi/validate
        * github.com/go-openapi/strfmt

You can get these now with: go get -u -f ./...

```
3. comment the last four lines in swagger/business.yaml
```yaml
#...
definitions:
  Business:
    type: object
    properties:
      children:
        type: array
        x-go-custom-tag: bson:"-"
        items:
          $ref: '#/definitions/Business'
      users:
        type: array
        x-go-custom-tag: bson:"users"
        items:
          type: object
#          properties:
#            role:
#              type: string
#              x-go-custom-tag: bson:"role"
```
execute `swagger generate model --with-flatten=expand -f swagger.yaml`
```shell
2020/07/09 18:07:10 preprocessing spec with option:  expand
2020/07/09 18:07:10 building a plan for generation
2020/07/09 18:07:10 generation target ./
2020/07/09 18:07:10 planning definitions
2020/07/09 18:07:10 planning operations
2020/07/09 18:07:10 grouping operations into packages
2020/07/09 18:07:10 planning meta data and facades
2020/07/09 18:07:10 rendering 1 models
2020/07/09 18:07:10 rendering 1 templates for model business
2020/07/09 18:07:10 name field business
2020/07/09 18:07:10 package field models
2020/07/09 18:07:10 creating generated file "business.go" in "models" as definition
2020/07/09 18:07:10 executed template asset:model
2020/07/09 18:07:10 Generation completed!

For this generation to compile you need to have some packages in your GOPATH:

        * github.com/go-openapi/validate
        * github.com/go-openapi/strfmt

You can get these now with: go get -u -f ./...

```
## Environment
swagger version: v0.24.0
go version: go1.14.2 darwin/amd64
OS:  macOS Catalina 10.15.3
