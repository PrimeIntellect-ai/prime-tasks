[4.0.10] Parsing http cookies with SameSite attribute - possible bug ?

## Environment Details
* Helidon Version: 4.0.10
* Helidon SE or Helidon MP: SE
* JDK version: 22.0.1
* OS: MacOS


----------

## Problem Description
The **SetCookie.parse(String setCookie)**  method of SetCookie.java (lines 83-133)  does not have a case statement for parsing [SameSite](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#syntax) attribute, although I see the Builder inner class below it does know  about samesite:
```java
private SameSite sameSite;
```

**Is this a bug?**
