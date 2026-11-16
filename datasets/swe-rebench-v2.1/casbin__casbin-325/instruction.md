Concurrency issues with custom adapter
I'm not exactly sure if it's because of the custom adapter I use, but I keep getting:
```
fatal error: concurrent map writes

goroutine 998 [running]:
runtime.throw(0x5ace54, 0x15)
	/tmp/go/1.12.6/go/src/runtime/panic.go:617 +0x5c fp=0x20d18d8 sp=0x20d18c4 pc=0x3ef68
runtime.mapassign_faststr(0x548b60, 0x21bf0e0, 0x5a286e, 0x1, 0x21c6368)
	/tmp/go/1.12.6/go/src/runtime/map_faststr.go:291 +0x424 fp=0x20d1908 sp=0x20d18d8 pc=0x239f8
github.com/casbin/casbin/v2.(*Enforcer).enforce(0x21bcc80, 0x0, 0x0, 0x21cef20, 0x3, 0x3, 0x214920c, 0x5a37da, 0x4)
	/home/pi/go/pkg/mod/github.com/casbin/casbin/v2@v2.1.0/enforcer.go:343 +0x128 fp=0x20d1adc sp=0x20d1908 pc=0x17bd4c
github.com/casbin/casbin/v2.(*Enforcer).Enforce(...)
	/home/pi/go/pkg/mod/github.com/casbin/casbin/v2@v2.1.0/enforcer.go:486
api/auth.(*CasbinConfig).CheckPermission(0x21c8cb0, 0x677dc0, 0x2228410, 0x83, 0x90, 0x0)
	/tmp/go/1.12.6/packages/src/api/auth/casbin_middleware.go:67 +0x154 fp=0x20d1b20 sp=0x20d1adc pc=0x48cb2c
api/auth.CasbinMiddlewareWithConfig.func1.1(0x677dc0, 0x2228410, 0x2228410, 0x21cee01)
	/tmp/go/1.12.6/packages/src/api/auth/casbin_middleware.go:51 +0x64 fp=0x20d1b44 sp=0x20d1b20 pc=0x48e928
api/auth.TokenMiddlewareWithConfig.func1.1(0x677dc0, 0x2228410, 0x4, 0x545890)
	/tmp/go/1.12.6/packages/src/api/auth/token_middleware.go:47 +0xf4 fp=0x20d1b68 sp=0x20d1b44 pc=0x48ed98
github.com/labstack/echo/v4/middleware.JWTWithConfig.func2.1(0x677dc0, 0x2228410, 0x5cb8f0, 0x1000)
	/home/pi/go/pkg/mod/github.com/labstack/echo/v4@v4.1.11/middleware/jwt.go:207 +0x32c fp=0x20d1bd8 sp=0x20d1b68 pc=0x38cbe4
github.com/labstack/echo/v4/middleware.RecoverWithConfig.func1.1(0x677dc0, 0x2228410, 0x0, 0x0)
	/home/pi/go/pkg/mod/github.com/labstack/echo/v4@v4.1.11/middleware/recover.go:78 +0xc4 fp=0x20d1c00 sp=0x20d1bd8 pc=0x38f558
github.com/labstack/echo/v4/middleware.GzipWithConfig.func1.1(0x677dc0, 0x2228410, 0x0, 0x0)
	/home/pi/go/pkg/mod/github.com/labstack/echo/v4@v4.1.11/middleware/compress.go:92 +0x194 fp=0x20d1c54 sp=0x20d1c00 pc=0x38af30
github.com/labstack/echo/v4/middleware.LoggerWithConfig.func2.1(0x677dc0, 0x2228410, 0x5b0844, 0x1b)
	/home/pi/go/pkg/mod/github.com/labstack/echo/v4@v4.1.11/middleware/logger.go:117 +0x134 fp=0x20d1cc0 sp=0x20d1c54 pc=0x38eba4
github.com/labstack/echo/v4/middleware.CORSWithConfig.func1.1(0x677dc0, 0x2228410, 0x8, 0x8)
	/home/pi/go/pkg/mod/github.com/labstack/echo/v4@v4.1.11/middleware/cors.go:121 +0x384 fp=0x20d1d74 sp=0x20d1cc0 pc=0x38b6ac
github.com/labstack/echo/v4.(*Echo).ServeHTTP.func1(0x677dc0, 0x2228410, 0x1, 0x0)
	/home/pi/go/pkg/mod/github.com/labstack/echo/v4@v4.1.11/echo.go:610 +0xec fp=0x20d1d9c sp=0x20d1d74 pc=0x361264
github.com/labstack/echo/v4/middleware.RemoveTrailingSlashWithConfig.func1.1(0x677dc0, 0x2228410, 0x1, 0x2)
	/home/pi/go/pkg/mod/github.com/labstack/echo/v4@v4.1.11/middleware/slash.go:118 +0x164 fp=0x20d1de8 sp=0x20d1d9c pc=0x38f7d8
github.com/labstack/echo/v4.(*Echo).ServeHTTP(0x20cc500, 0x672a10, 0x23ba900, 0x2122000)
	/home/pi/go/pkg/mod/github.com/labstack/echo/v4@v4.1.11/echo.go:616 +0x234 fp=0x20d1e10 sp=0x20d1de8 pc=0x359280
net/http.serverHandler.ServeHTTP(0x20a4800, 0x672a10, 0x23ba900, 0x2122000)
	/tmp/go/1.12.6/go/src/net/http/server.go:2774 +0x88 fp=0x20d1e2c sp=0x20d1e10 pc=0x2fa3e0
net/http.(*conn).serve(0x2435260, 0x6733f0, 0x21cfa40)
	/tmp/go/1.12.6/go/src/net/http/server.go:1878 +0x7e4 fp=0x20d1fdc sp=0x20d1e2c pc=0x2f69a0
runtime.goexit()
	/tmp/go/1.12.6/go/src/runtime/asm_arm.s:868 +0x4 fp=0x20d1fdc sp=0x20d1fdc pc=0x6b574
created by net/http.(*Server).Serve
	/tmp/go/1.12.6/go/src/net/http/server.go:2884 +0x298
```

So it fails around `functions[key] = util.GenerateGFunction(rm)`.

Here's the custom adapter I use:
```go
package auth

import (
	"bufio"
	"errors"
	"os"
	"strings"

	"github.com/casbin/casbin/v2/model"

	"api/user"
)

type Adapter struct {
	fPath string
}

// No AutoSave
// https://casbin.org/docs/en/adapters#how-to-write-an-adapter
// https://github.com/casbin/casbin/blob/master/persist/adapter.go
func (a *Adapter) AddPolicy(sec string, ptype string, rule []string) error {
	return errors.New("Not implemented")
}

func (a *Adapter) RemovePolicy(sec string, ptype string, rule []string) error {
	return errors.New("Not implemented")
}

func (a *Adapter) RemoveFilteredPolicy(sec string, ptype string, fieldIndex int, fieldValues ...string) error {
	return errors.New("Not implemented")
}

func NewAdapter(fPath string) *Adapter {
	return &Adapter{fPath}
}

func (a *Adapter) LoadPolicy(m model.Model) error {
	if err := a.fromFile(m, update); err != nil {
		return err
	}

	f := user.Find()
	if err := f.Error(); err != nil {
		return err
	}

	for _, user := range f.Users() {
		update(m, user.Permissions())
	}

	return nil
}

// TODO: Figure out if we need to save
func (a *Adapter) SavePolicy(m model.Model) error {
	return errors.New("Not implemented")
}

func update(m model.Model, tokens []string) {
	key := tokens[0]
	sec := key[:1]
	m[sec][key].Policy = append(m[sec][key].Policy, tokens[1:])
}

func (a *Adapter) fromFile(m model.Model, h func(model.Model, []string)) error {
	f, err := os.Open(a.fPath)
	if err != nil {
		return err
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		p := strings.TrimSpace(scanner.Text())
		// Skip comments and/or empty strings
		if p == "" || strings.HasPrefix(p, "#") {
			continue
		}
		tokens := strings.Split(p, ",")
		for i := 0; i < len(tokens); i++ {
			tokens[i] = strings.TrimSpace(tokens[i])
		}
		h(m, tokens)
	}
	return scanner.Err()
}
```

And the middleware I use with [echo](https://echo.labstack.com):
```go
package auth

import (
	"github.com/casbin/casbin/v2"
	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"

	"api/utils"
)

type (
	// Config defines the config for CasbinAuth middleware
	CasbinConfig struct {
		// Skipper defines a function to skip middleware
		Skipper middleware.Skipper

		// Enforcer defines the CasbinAuth main rule.
		// Required.
		Enforcer *casbin.Enforcer
	}
)

var (
	// DefaultCasbinConfig is the default CasbinAuth middleware config
	DefaultCasbinConfig = CasbinConfig{
		Skipper: middleware.DefaultSkipper,
	}
)

// CasbinMiddleware returns a CasbinAuth middleware
func CasbinMiddleware(ce *casbin.Enforcer) echo.MiddlewareFunc {
	c := DefaultCasbinConfig
	c.Enforcer = ce
	return CasbinMiddlewareWithConfig(c)
}

// TODO: Make PR for echo-contrib for jwt support
// CasbinMiddlewareWithConfig returns a CasbinAuth middleware with config
func CasbinMiddlewareWithConfig(config CasbinConfig) echo.MiddlewareFunc {
	// Defaults
	if config.Skipper == nil {
		config.Skipper = DefaultCasbinConfig.Skipper
	}

	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			if config.Skipper(c) {
				return next(c)
			}

			if pass, err := config.CheckPermission(c); err == nil && pass {
				return next(c)
			} else if err != nil {
				return utils.ServerError(err)
			}

			return echo.ErrForbidden
		}
	}
}

// CheckPermission checks the user/method/path combination from the request.
// Returns true (permission granted) or false (forbidden)
func (a *CasbinConfig) CheckPermission(c echo.Context) (bool, error) {
	username := GetUsername(c)
	req := c.Request()
	return a.Enforcer.Enforce(username, req.URL.Path, req.Method)
}
```

And the way I init and use it:
```go
func main() {
        e := echo.New()

        // ACL
	// https://echo.labstack.com/middleware/casbin-auth
	a := auth.NewAdapter(os.Getenv("AUTH_POLICY"))
	ce, err := casbin.NewEnforcer(os.Getenv("AUTH_MODEL"), a)
	if err != nil {
		e.Logger.Error(err.Error())
		return
	}

	acl := auth.CasbinMiddlewareWithConfig(auth.CasbinConfig{
		Skipper:  authSkipper,
		Enforcer: ce,
	})
	e.Use(acl)
}
```
