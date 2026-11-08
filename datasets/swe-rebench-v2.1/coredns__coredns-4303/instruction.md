Non-existent CNAME target in the same zone should be returned with NXDOMAIN instead of NOERROR rcode
Hi,

This is related to if 'A CNAME B' exists in a zone, but B (related to the same zone) does not exist, then the return code should be NXDOMAIN.  [RFC 6604](https://tools.ietf.org/html/rfc6604#section-3) mentions that
> When chains are followed the RCODE in the ultimate DNS response MUST BE set based on the final query cycle leading to that
>       response.


Consider the following sample zone file

|  	|  	|  	|  	|
|-	|-	|-	|-	|
| example.com. 	| 500 | SOA 	| ns1.outside.com. root.example.com. 3 604800 86400 2419200 604800 	|
| example.com. 	| 500 | NS 	| ns1.outside.com.  	|
| b.c.example.com. 	| 500 | CNAME | c.c.example.com.  	|
| c.c.example.com. 	| 500 | CNAME	| d.c.example.com.  	|

For the query _<b.c.example.com. , A>_, the Coredns server returns the following response:
```
          "opcode QUERY",
          "rcode NOERROR",
          "flags QR AA",
          ";QUESTION",
          "b.c.campus.edu. IN A",
          ";ANSWER",
          "b.c.example.com. 500 IN CNAME c.c.example.com.",
          "c.c.example.com. 500 IN CNAME d.c.example.com.",
          ";AUTHORITY",
          "example.com. 500 IN NS ns1.outside.com.",
          ";ADDITIONAL"
```

**What you expected to happen**:
The expected response is the same as above except that the `rcode` should be `NXDOMAIN`.

**Environment**:

- the version of CoreDNS: `CoreDNS-1.8.0  linux/amd64, go1.15.3, 054c9ae`
- Corefile:
```
example.com:53 {
    file db.example.com
    log
    errors
}
```
- OS: Ubuntu 18
