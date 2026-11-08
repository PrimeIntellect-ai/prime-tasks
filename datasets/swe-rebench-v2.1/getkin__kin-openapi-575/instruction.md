openapi2conv does not respect "produces" keyword
It seems like when using `openapi2conv.ToV3`, the result content-type is always JSON. Please see the [example](https://goplay.tools/snippet/qeaIZN5khfd) (also pasted below). The output is `application/json` while the `produces` field is `application/toml`.

[HIDDEN]

Hope I'm correctly defining a content-type for response in openapi v2, and using openapi2conv correctly as well.

Thanks.

---

```go
package main

import (
	"fmt"

	"github.com/getkin/kin-openapi/openapi2"
	"github.com/getkin/kin-openapi/openapi2conv"
	"github.com/getkin/kin-openapi/openapi3"
	"github.com/invopop/yaml"
)

func v2v3YAML(spec2 []byte) (doc3 *openapi3.T, err error) {
	var doc2 openapi2.T
	if err = yaml.Unmarshal(spec2, &doc2); err != nil {
		return
	}
	doc3, err = openapi2conv.ToV3(&doc2)
	return
}

func main() {
	spec := []byte(`paths:
  /ping:
    get:
      produces:
        - application/toml
      responses:
        200:
          schema:
            type: object
            properties:
              username:
                type: string
                description: The user name.`)

	v3, err := v2v3YAML(spec)
	if err != nil {
		panic(err)
	}

	yamlV3, err := yaml.Marshal(v3)
	if err != nil {
		panic(err)
	}

	fmt.Println(string(yamlV3))
}
```

Got:
```yaml
components: {}
info:
    title: ""
    version: ""
openapi: 3.0.3
paths:
    /ping:
        get:
            responses:
                "200":
                    content:
                        application/json:
                            schema:
                                properties:
                                    username:
                                        description: The user name.
                                        type: string
                                type: object
                    description: ""

```

Expected:
```yaml
components: {}
info:
    title: ""
    version: ""
openapi: 3.0.3
paths:
    /ping:
        get:
            responses:
                "200":
                    content:
                        application/toml:
                            schema:
                                properties:
                                    username:
                                        description: The user name.
                                        type: string
                                type: object
                    description: ""
```
