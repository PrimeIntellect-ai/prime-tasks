SAML connector - nil pointer dereference exception
I'm attempting to set up a SAML2 connector in a k8s cluster for one of our internal environments. While testing this saml setup, the following nil pointer exception happens on every request:

```
2020-07-03 22:28:03.610634 I | http: panic serving 172.16.0.96:60284: runtime error: invalid memory address or nil pointer dereference
goroutine 184 [running]:
net/http.(*conn).serve.func1(0xc000153e00)
        /usr/local/go/src/net/http/server.go:1767 +0x139
panic(0xf0d960, 0x185a270)
        /usr/local/go/src/runtime/panic.go:679 +0x1b2
github.com/beevik/etree.(*Element).dup(0x0, 0x0, 0x9, 0xc000171428)
        /go/pkg/mod/github.com/beevik/etree@v1.1.0/etree.go:965 +0x37
github.com/beevik/etree.(*Element).Copy(...)
        /go/pkg/mod/github.com/beevik/etree@v1.1.0/etree.go:350
github.com/russellhaering/goxmldsig.(*ValidationContext).Validate(0xc0000fccc0, 0x0, 0x1086f79, 0x25, 0x1066d29)
        /go/pkg/mod/github.com/russellhaering/goxmldsig@v0.0.0-20180430223755-7acd5e4a6ef7/validate.go:454 +0x38
github.com/dexidp/dex/connector/saml.verifyResponseSig(0xc0000fccc0, 0xc00018a000, 0xa86, 0xa86, 0xa86, 0xa86, 0x0, 0x0, 0x419eae, 0xc000183000)
        /go/src/github.com/dexidp/dex/connector/saml/saml.go:599 +0x1bb
github.com/dexidp/dex/connector/saml.(*provider).HandlePOST(0xc00008eb60, 0x1060101, 0xc000186000, 0xe08, 0xc000037020, 0x19, 0x0, 0x0, 0x0, 0x0, ...)
        /go/src/github.com/dexidp/dex/connector/saml/saml.go:297 +0x12fb
github.com/dexidp/dex/server.(*Server).handleConnectorCallback(0xc000315600, 0x11d5060, 0xc0002ca8c0, 0xc00049de00)
        /go/src/github.com/dexidp/dex/server/handlers.go:455 +0xe54
github.com/dexidp/dex/server.newServer.func7(0x11d5060, 0xc0002ca8c0, 0xc00049de00)
        /go/src/github.com/dexidp/dex/server/server.go:312 +0x175
net/http.HandlerFunc.ServeHTTP(0xc0001465d0, 0x11d5060, 0xc0002ca8c0, 0xc00049de00)
        /usr/local/go/src/net/http/server.go:2007 +0x44
github.com/gorilla/mux.(*Router).ServeHTTP(0xc0000180c0, 0x11d5060, 0xc0002ca8c0, 0xc00049dc00)
        /go/pkg/mod/github.com/gorilla/mux@v1.7.3/mux.go:212 +0xe2
github.com/dexidp/dex/server.(*Server).ServeHTTP(0xc000315600, 0x11d5060, 0xc0002ca8c0, 0xc00049dc00)
        /go/src/github.com/dexidp/dex/server/server.go:330 +0x58
net/http.serverHandler.ServeHTTP(0xc0004381c0, 0x11d5060, 0xc0002ca8c0, 0xc00049dc00)
        /usr/local/go/src/net/http/server.go:2802 +0xa4
net/http.(*conn).serve(0xc000153e00, 0x11d82e0, 0xc00015df00)
        /usr/local/go/src/net/http/server.go:1890 +0x875
created by net/http.(*Server).Serve
        /usr/local/go/src/net/http/server.go:2928 +0x384
```

The following is our SAML connector config, which is not the only connector we use, but it's the one that's relevant for now:

```yaml
  config.yaml: |-
    issuer: https://dex-ad.<domain>
    storage:
      type: kubernetes
      config:
        inCluster: true
    logger:
      format: json
      level: debug
    web:
      http: 0.0.0.0:8080
    grpc:
      addr: 0.0.0.0:8090
      tlsCert: /etc/dex/tls/grpc/server/tls.crt
      tlsKey: /etc/dex/tls/grpc/server/tls.key
      tlsClientCA: /etc/dex/tls/grpc/ca/tls.crt
    connectors:
    - type: saml
      id: organization
      name: ORGANIZATION
      config:
        ssoURL: https://adfs.<test domain>/adfs/ls/idpinitiatedSignOn.aspx
        redirectURI: https://dex-ad.<domain>/callback
        entityIssuer: https://dex-ad.<domain>/callback
        usernameAttr: name
        emailAttr: email
        caData: <REDACTED>
      insecureSkipSignatureValidation: false

```

When attempting to test the authentication, the following happens:

browse to site login
forwards to dex login
select <LAB> login button
presents credential login page/ credentials entered
wait for about a minutes
presented with 502 gateway error from ingress controller. URL is callback url: `https://dex-ad.<domain>/callback`

dex logs show output from above.

### Additional contract requirements

- When a SAML response cannot be signature-validated because it lacks the XML element needed for validation (the document root, or the `Assertion` element when the root is not signed), the connector must return an error for that login attempt. It must not panic.
