Jwts.builder - audience cannot be add without calling add()
**Describe the bug**
When using builder to create a token adding audience needs to be followed by `and()`. This behaviour is not documented and it is inconsistent (eg. claims do not need that).

**To Reproduce**
Try to add audience to a builder by calling `builder.audience().add("my-web")`;
Test case:
```
  @Test
  public void testJwtBuilder(){
      //working
      JwtBuilder builder = Jwts.builder();
      builder.audience().add("my-web").and();
      String json = builder.compact();

      String decoded = new String(Base64.getDecoder().decode(json.split("\\.")[1]));
      assertThat(decoded).contains("aud");

      // Failing test scenario
      JwtBuilder builder2 = Jwts.builder();
      // missing and()
      builder2.audience().add("my-web");
      String json2 = builder2.compact();

      String decoded2 = new String(Base64.getDecoder().decode(json2.split("\\.")[1]));
      assertThat(decoded2).contains("aud");
  }
```

**Expected behavior**
Adding audience to a builder does not need to be followed by `and()`
