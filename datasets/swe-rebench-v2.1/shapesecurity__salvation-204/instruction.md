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

- A hash source (`'sha256-…'`, `'sha384-…'` or `'sha512-…'`) must carry a base64 value that decodes to exactly 32, 48 or 64 bytes respectively. A hash value that decodes to any other length must be reported as an error, and the policy must not keep that source expression.
- A correctly sized digest must be accepted and serialized back unchanged.
