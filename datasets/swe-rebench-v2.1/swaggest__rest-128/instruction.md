Add support for cookies in response
Similar to having `header` field tags in output structure, we can have `cookie`. However, cookies have more additional parameters that perhaps can be configured as field tag options, e.g. `cookie="foo,httponly,path=/foo"`.

### Additional contract requirements

- When output fields use `cookie:"coo,httponly,path=/foo"` with value `123` and `cookie:"coo2,httponly,secure,samesite=lax,path=/foo,max-age=86400"` with value `true`, the response's `Set-Cookie` values must be, in order, `coo=123; Path=/foo; HttpOnly` and `coo2=true; Path=/foo; Max-Age=86400; HttpOnly; Secure; SameSite=Lax`.
- When an output field uses `cookie:"coo,httponly,path:/foo"` with value `123`, its `Set-Cookie` value must be exactly `coo=123; HttpOnly`.
