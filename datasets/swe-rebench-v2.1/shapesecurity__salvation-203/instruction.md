Wrong validation of HashSource
**What is the problem?**
Generating a SHA-256 hash - I didn't test the other algorithms - with salvation 2.5.0 and checking with https://cspvalidator.org fails.

**How to reproduce?**
1. Generate `script-src `directive containing SHA-256 hash:

```java
		Origin origin = URI.parse("http://localhost");
		Policy policy = new Policy(origin);
		policy.addDirective(new ScriptSrcDirective(Collections.singleton(new HashSource(HashSource.HashAlgorithm.SHA256, new Base64Value(Base64.getEncoder().encodeToString(MessageDigest.getInstance("SHA-256").digest("function foo() { bla('123'); }".getBytes(/*StandardCharsets.US_ASCII*/))))))));
		System.out.println(policy.show());

```
 Return value: `script-src 'sha256-YWFmMzU3YWU0ZDYzM2IzYWEzZTIzOTg2Yjk1ZGFjYWQ2YzgyZDdhZDM4MTAyZWUwMjNmZjk5M2IwNWUzN2RkOA=='`

2. Test it with [cspvalidator](https://cspvalidator.org/#headerValue%5B%5D=script-src+'sha256-YWFmMzU3YWU0ZDYzM2IzYWEzZTIzOTg2Yjk1ZGFjYWQ2YzgyZDdhZDM4MTAyZWUwMjNmZjk5M2IwNWUzN2RkOA%3D%3D'&strategy=intersection):

![image](https://user-images.githubusercontent.com/13161711/43185117-3ef79a06-8feb-11e8-8474-f17a4667f380.png)

### Additional contract requirements

- HashSource validation must also accept and preserve these SHA-384 and SHA-512 source expressions when parsing and showing a policy: `'sha384-NzY4NDEyMzIwZjdiMGFhNTgxMmZjZTQyOGRjNDcwNmIzY2FlNTBlMDJhNjRjYWExNmE3ODIyNDliZmU4ZWZjNGI3ZWYxY2NiMTI2MjU1ZDE5NjA0N2RmZWRmMTdhMGE5'` and `'sha512-ZWUyNmIwZGQ0YWY3ZTc0OWFhMWE4ZWUzYzEwYWU5OTIzZjYxODk4MDc3MmU0NzNmODgxOWE1ZDQ5NDBlMGRiMjdhYzE4NWY4YTBlMWQ1Zjg0Zjg4YmM4ODdmZDY3YjE0MzczMmMzMDRjYzVmYTlhZDhlNmY1N2Y1MDAyOGE4ZmY='`.
