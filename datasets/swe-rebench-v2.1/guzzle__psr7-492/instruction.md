Urgent - v2.1.1 - MessageTrait assertValue broken
**PHP version**: 7.4.27 (hint: `php --version`)

**Description**
I updated my dependencies, and guzzlehttp/psr7 was updated to v2.1.1. This broke an integration with a third party API that I'm working with. (Largest credit card payment processor in Scandiavia).

I have traced it down to the changes introduced in MessageTrait for the method `assertValue`.
When the response (which I am not in control over), contains the following header, I get an InvalidArgumentException XXX is not a valid header value.

```
X-Iinfo: 12-34567890-123456789 AAAA BC(12 34 5) DE(1234567890123 123) a(1 2 3 4) b(1 2) A1
```

I have changed the actual values from the header, as I'm not sure if it contains confidential information. The relevant part here is the whitespaces, which failes the parsing introduced in 2.1.1.


**How to reproduce**
Add the above header to a response.

**Possible Solution**
[HIDDEN]

**Additional context**

### Additional contract requirements

- Accept a response containing the reported whitespace-containing `X-Iinfo` header value instead of rejecting it as an invalid header value.
