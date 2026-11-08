A single audience value gets converted into a set with one entry
**Describe the bug**

In the scenario when we first build claims with `DefaultClaimsBuilder` and then pass them to `JwtBuilder`, a single audience value gets converted somewhere on the way from `String` to `Set<String>`. **This is a breaking change for the APIs, which expect a string audience value.**

**To Reproduce**
Steps to reproduce the behavior:
1. Build claims:
```java
var claims = new DefaultClaimsBuilder().audience().single("https://login.salesforce.com").build();
```
2. Check the type of the claim value of in Debugger (must be `String`):
![image](https://github.com/jwtk/jjwt/assets/26978790/dc84e5ec-a275-4a2f-ae6b-a9a95228ce15)
3. Create a JWT builder with the claims object:
```java
var jwtBuilder = Jwts.builder().claims(claims);
```
4. Check again the type of the claim value in Debugger (see `jwtBuilder`; this time it's `Set<String>`):
![image](https://github.com/jwtk/jjwt/assets/26978790/d672db7d-1ccd-4f4b-b581-ee76938d84e9)


**Expected behavior**
In case of using `audience().single(...)` the type of the `audience` claim should stay `String` after calling `claims(...)` on the JWT builder.

**Workaround**
Note, if setting the claim directly on the JWT builder, the type is preserved:
```java
var jwtBuilder = Jwts.builder().audience().single("https://login.salesforce.com");
```
