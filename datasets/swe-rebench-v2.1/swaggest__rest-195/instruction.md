Unable to set default values for custom typed strings
**Describe the bug**
I'm trying to build an enum type that can be used for input. As a part of this, I'd like to be able to set a default value for the enum field as well. I'd like to be able to define this in code (for reuse) rather than as a struct tag (i.e make our actual inputs/outputs match the documentation).

However, when I try to use a custom type with the default struct tags, it seems as though the parser expects a json string/object rather than a string value. You can use a json string to get past this, but then default does something weird. Concrete example below.

**To Reproduce**
```
package main_test

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/swaggest/rest/web"
	"github.com/swaggest/usecase"
)

type Discover string

const (
	DiscoverAll  Discover = "all"
	DiscoverNone Discover = "none"
)

func (d *Discover) Enum() []any {
	return []any{DiscoverAll, DiscoverNone}
}

func TestFoo(t *testing.T) {
	type NewThing struct {
		DiscoverMode *Discover `json:"discover,omitempty" default:"all"`
	}

	s := web.DefaultService()

	s.Post("/foo", usecase.NewInteractor(func(ctx context.Context, input NewThing, output *string) error {
		disc := string(*input.DiscoverMode)
		*output = disc

		return nil
	}))

	req, err := http.NewRequest(http.MethodPost, "/foo", bytes.NewReader([]byte(`{}`)))
	require.NoError(t, err)
	req.Header.Set("Content-Type", "application/json")
	rw := httptest.NewRecorder()

	s.ServeHTTP(rw, req)
	assert.Equal(t, `"all" `, rw.Body.String())
}
```

**Observed behavior**

```
=== RUN   TestFoo
--- FAIL: TestFoo (0.00s)
panic: DiscoverMode: parsing default as JSON: invalid character 'a' looking for beginning of value [recovered]
        panic: DiscoverMode: parsing default as JSON: invalid character 'a' looking for beginning of value
```

**Expected behavior**
The API returns `all`.

Side note: you can change this so it reads `default:"\"all\""` -- then the input validation passes, but your default ends up as the quoted json string `"all"`, not `all` (i.e. it is not possible to produce the valid enum option).


--

I'm happy to make a contribution here if you can point me in the right direction. I did step through the code a bit. I tried Implementing a TextUn/Marshaller so that maybe the type would properly get set as a string in `jsonschema-go/reflect.go`, but that didn't seem to make anything better on the version I was using. [HIDDEN]

### Additional contract requirements

For reusable defaults declared in a custom string type's prepared JSON Schema, omitted JSON request fields must receive the schema default. For custom typed-string fields with a `default` struct tag, the tag value is the enum string itself (for example, `all`), not a JSON-encoded string.
