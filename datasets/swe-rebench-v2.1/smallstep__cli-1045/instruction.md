[Bug]: Step CLI panics when inspecting improperly encoded certificate
### Steps to Reproduce

First of all, thanks so much for this awesome tool. It's a breath of fresh air from using openssl and I can't wait to start playing with the CA too.

This may be a roundabout way to replicate it, but this is how I produced the certificate:

```
step certificate create --profile=root-ca --kty=OKP TestRootCA ca.crt ca.priv --no-password --insecure
step certificate create --csr --profile=leaf --kty=OKP acme.com server.csr server.priv --no-password --insecure
step certificate sign --not-before 0h --not-after 1h .\server.csr .\ca.crt .\ca.priv | out-file -encoding utf8 server.crt
```

Then:

```
step certificate inspect server.crt
```

panics:

```
Smallstep CLI/0.24.4 (windows/amd64)
Release Date: 2023-05-11T19:52:34Z

panic: runtime error: index out of range [0] with length 0 [recovered]
        panic: runtime error: index out of range [0] with length 0

goroutine 1 [running]:
main.panicHandler()
        ./main.go:147 +0x245
panic({0x127bac0, 0xc0006283f0})
        runtime/panic.go:884 +0x212
github.com/smallstep/cli/command/certificate.inspectAction(0xc000a28420)
        github.com/smallstep/cli/command/certificate/inspect.go:254 +0x709
github.com/urfave/cli.HandleAction({0x111e820?, 0x143b7a8?}, 0x7?)
        github.com/urfave/cli@v1.22.13/app.go:522 +0xb0
github.com/urfave/cli.Command.Run({{0x132f19e, 0x7}, {0x0, 0x0}, {0x0, 0x0, 0x0}, {0x13b1844, 0x39}, {0x13d2492, ...}, ...}, ...)
        github.com/urfave/cli@v1.22.13/command.go:175 +0x67b
github.com/urfave/cli.(*App).RunAsSubcommand(0xc00071bc00, 0xc000a28160)
        github.com/urfave/cli@v1.22.13/app.go:405 +0x927
github.com/urfave/cli.Command.startApp({{0x133c01f, 0xb}, {0x0, 0x0}, {0x0, 0x0, 0x0}, {0x13bb1ca, 0x43}, {0x13bfba2, ...}, ...}, ...)
        github.com/urfave/cli@v1.22.13/command.go:380 +0x6e7
github.com/urfave/cli.Command.Run({{0x133c01f, 0xb}, {0x0, 0x0}, {0x0, 0x0, 0x0}, {0x13bb1ca, 0x43}, {0x13bfba2, ...}, ...}, ...)
        github.com/urfave/cli@v1.22.13/command.go:103 +0x845
github.com/urfave/cli.(*App).Run(0xc00071ba40, {0xc0000a2040, 0x4, 0x4})
        github.com/urfave/cli@v1.22.13/app.go:277 +0x8c7
main.main()
        ./main.go:119 +0x615
```

I believe this has to do with the `utf8` encoding, b/c if I use `ascii` instead the inspection works:

```
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number: 130535302445038795180957784638024798754 (0x62342f4d99f9ebf88d27df5c7bfb5222)
    Signature Algorithm: Ed25519
        Issuer: CN=TestRootCA
        Validity
            Not Before: Oct 19 17:25:25 2023 UTC
            Not After : Oct 19 18:25:25 2023 UTC
        Subject: CN=acme.com
        Subject Public Key Info:
            Public Key Algorithm: Ed25519
                Public-Key: (32 bit)
                    6b:fc:1f:09:54:81:1d:ec:cd:3e:39:a0:d1:6e:6f:
                    1f:b2:a1:12:2c:eb:d4:4f:a6:5b:8a:57:b1:dc:da:
                    7e:cd
        X509v3 extensions:
            X509v3 Key Usage: critical
                Digital Signature
            X509v3 Extended Key Usage:
                Server Authentication, Client Authentication
            X509v3 Subject Key Identifier:
                FB:FD:D1:5E:87:EF:9B:53:6A:ED:A7:1E:3E:CD:C6:12:EF:45:A8:34
            X509v3 Authority Key Identifier:
                keyid:B0:BB:BB:21:C4:62:72:83:DE:2C:99:CC:FA:67:9E:80:B3:F3:84:C2
            X509v3 Subject Alternative Name:
                DNS:acme.com
    Signature Algorithm: Ed25519
         ea:90:7c:fb:f1:12:cf:da:22:3b:69:1c:72:83:b7:d4:61:14:
         00:51:aa:db:c3:be:38:a7:4e:87:35:ef:72:33:cb:94:cd:74:
         09:41:5d:57:4e:83:da:15:fb:b7:ff:da:47:e9:5f:31:6b:21:
         f1:55:65:41:27:5c:09:18:c0:07
```

### Your Environment

In the panic message above.

### Expected Behavior

Step CLI should be able to gracefully handle the improper encoding and perhaps say a bit about what isn't valid about the file.

### Actual Behavior

panic index out of bounds

### Additional Context

In general, I think it might be useful if `step certificate sign` could output the signed certificate directly to an output file to avoid encoding issues like this one.

### Contributing

Vote on this issue by adding a 👍 reaction.
To contribute a fix for this issue, leave a comment (and link to your pull request, if you've opened one already).

### Additional contract requirements

- `step certificate inspect` must not panic when the certificate file begins with a UTF BOM. If inspection succeeds, the certificate details are printed and the output begins with `Certificate:`.
