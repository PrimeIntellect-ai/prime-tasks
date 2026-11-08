dnsimple: DNS-01 challenge for wildcard: NXDOMAIN then panic (nil pointer dereference)
On commit ad20bf90ff5479cb8c63aef7e0f773b3c7e35835 (current master HEAD).

When obtaining a wildcard certificate, I get a panic using the dnsimple DNS provider:

```
 2018/09/26 04:25:13 [INFO] [*.subdomain.mydomain.net] acme: Obtaining bundled SAN certificate
 2018/09/26 04:25:13 [INFO] [*.subdomain.mydomain.net] AuthURL: https://acme-v02.api.letsencrypt.org/acme/authz/wRRYQyK5NOtKPgWJ64WraUKp3Uwa...
 2018/09/26 04:25:13 [INFO] [subdomain.mydomain.net] acme: Preparing to solve DNS-01
Sep 26 04:25:13 [ERROR] Server returned error NXDOMAIN, mitigating potential DNS violation DVE-2018-0001, retrying transaction with reduced feature level UDP.
Sep 26 04:25:13 [ERROR] Server returned error NXDOMAIN, mitigating potential DNS violation DVE-2018-0001, retrying transaction with reduced feature level UDP.
 panic: runtime error: invalid memory address or nil pointer dereference
 [signal SIGSEGV: segmentation violation code=0x1 addr=0x30 pc=0x8d779f]
 goroutine 1 [running]:
 github.com/xenolf/lego/providers/dns/dnsimple.(*DNSProvider).Present(0xc00017e660, 0xc00053c4e0, 0x18, 0xc0003b0060, 0x2b, 0xc0000606c0, 0x57, 0x0, 0xc00019ef60)
         /Users/matt/Dev/src/github.com/xenolf/lego/providers/dns/dnsimple/dnsimple.go:99 +0x13f
 github.com/xenolf/lego/acme.(*dnsChallenge).PreSolve(0xc000544240, 0xc000054930, 0x6a, 0xc0005283c0, 0x6, 0xc0005283c6, 0x7, 0xc0003b0060, 0x2b, 0x0, ...)
         /Users/matt/Dev/src/github.com/xenolf/lego/acme/dns_challenge.go:97 +0x17d
 github.com/xenolf/lego/acme.(*Client).solveChallengeForAuthz(0xc0001320c0, 0xc0001f83c0, 0x1, 0x1, 0x0, 0x0)
         /Users/matt/Dev/src/github.com/xenolf/lego/acme/client.go:601 +0x3c6
 github.com/xenolf/lego/acme.(*Client).ObtainCertificate(0xc0001320c0, 0xc000521020, 0x1, 0x1, 0x4b5a01, 0x0, 0x0, 0x0, 0x0, 0xc00001d980, ...)
         /Users/matt/Dev/src/github.com/xenolf/lego/acme/client.go:434 +0x2b3
```

The NXDOMAIN error is strange, since the domain definitely exists, and in fact this same code was running in production just fine before moving from an earlier commit to this latest one.

However, the panic happens even without NXDOMAIN errors (here's another try from this morning):

```
2018/09/26 16:31:42 [INFO] [subdomain1.mydomain.net] The server validated our request
2018/09/26 16:31:42 [INFO] [subdomain1.mydomain.net] acme: Validations succeeded; requesting certificates
2018/09/26 16:31:42 http: TLS handshake error from 70.176.85.69:63561: remote error: tls: bad certificate
2018/09/26 16:31:42 [INFO] [subdomain1.mydomain.net] Server responded with a certificate.
2018/09/26 16:31:42 [INFO] [*.subdomain2.mydomain.net] acme: Obtaining bundled SAN certificate
2018/09/26 16:31:43 [INFO] [*.subdomain2.mydomain.net] AuthURL: https://acme-staging-v02.api.letsencrypt.org/acme/authz/mP0GDa8a6Kh4dNn2Tri4SybZlu0TV...
2018/09/26 16:31:43 [INFO] [subdomain2.mydomain.net] acme: Preparing to solve DNS-01
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x30 pc=0x8d7a9f]

goroutine 1 [running]:
github.com/xenolf/lego/providers/dns/dnsimple.(*DNSProvider).Present(0xc000180660, 0xc00057c4a0, 0x18, 0xc0002d0090, 0x2b, 0xc0005201e0, 0x57, 0x0, 0xc000658f60)
	/Users/matt/Dev/src/github.com/xenolf/lego/providers/dns/dnsimple/dnsimple.go:99 +0x13f
github.com/xenolf/lego/acme.(*dnsChallenge).PreSolve(0xc00050e220, 0xc000068100, 0x71, 0xc000556628, 0x6, 0xc0005566c0, 0x7, 0xc0002d0090, 0x2b, 0x0, ...)
	/Users/matt/Dev/src/github.com/xenolf/lego/acme/dns_challenge.go:100 +0x17d
github.com/xenolf/lego/acme.(*Client).solveChallengeForAuthz(0xc0001360c0, 0xc000406600, 0x1, 0x1, 0x0, 0x0)
	/Users/matt/Dev/src/github.com/xenolf/lego/acme/client.go:603 +0x3c6
github.com/xenolf/lego/acme.(*Client).ObtainCertificate(0xc0001360c0, 0xc00056e4f0, 0x1, 0x1, 0x4b5a01, 0x0, 0x0, 0x0, 0xc00054c1e0, 0x0, ...)
	/Users/matt/Dev/src/github.com/xenolf/lego/acme/client.go:437 +0x2b3
```

I'm configuring the DNS provider like this:

```go
dnsimpleClient, err := dnsimple.NewDNSProviderCredentials(Config.DNS.Provider.DNSimpleOauthToken, Config.DNS.Provider.DNSimpleBaseURL)
if err != nil {
	return fmt.Errorf("constructing DNS provider: %v", err)
}
```

With no error.

Somehow, the config appears to be set to nil at some point.

**Here's my workaround/fix:**  reverting to an older commit before de3accf531a7dd4eff65ae20e9787fc62045b674, such as 6588bc6fa5b9d47abae1b6c40ef73e166f44fa95, resolves both errors: no NXDOMAIN and no panic:

```
2018/09/26 10:42:02 [INFO] [*.subdomain2.mydomain.net] acme: Obtaining bundled SAN certificate
2018/09/26 10:42:03 [INFO] [*.subdomain2.mydomain.net] AuthURL: https://acme-v02.api.letsencrypt.org/acme/authz/wRRYQyK5NOtKPgWJ64WraUKp3UwaF...
2018/09/26 10:42:03 [INFO] [subdomain2.mydomain.net] acme: Trying to solve DNS-01
2018/09/26 10:42:03 [INFO] [subdomain2.mydomain.net] Checking DNS record propagation using [127.0.0.53:53]
2018/09/26 10:42:15 [INFO] [subdomain2.mydomain.net] The server validated our request
2018/09/26 10:42:15 [INFO] [*.subdomain2.mydomain.net] acme: Validations succeeded; requesting certificates
2018/09/26 10:42:16 [INFO] [*.subdomain2.mydomain.net] Server responded with a certificate.
```

I suspect de3accf531a7dd4eff65ae20e9787fc62045b674 may be the problem (though I haven't verified this) because it introduces the the log message that is output just before the panic.

I haven't had time to narrow down which commit broke it since I have to recompile, re-upload, and re-run it all, which takes some time (I have very slow uplink). So some help or input from people with familiarity with the code and its recent changes would be appreciated!

Thanks for your great work on lego -- really awesome stuff. Probably one of the most useful libraries out there.

/cc @captncraig
