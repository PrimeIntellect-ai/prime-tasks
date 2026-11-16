Add DialContext function
I want Context to be used when dialing.
So I want DialContext.

By default you should use Dialer.DialContext.
https://golang.org/pkg/net/#Dialer.DialContext

### Additional contract requirements

- Add a public function `DialContext(ctx context.Context, network string, address string, options ...DialOption) (Conn, error)` in package `redis` (file `redis/conn.go`).
- Add a public function `DialContextFunc(f func(ctx context.Context, network string, addr string) (net.Conn, error)) DialOption` in package `redis` (file `redis/conn.go`).
