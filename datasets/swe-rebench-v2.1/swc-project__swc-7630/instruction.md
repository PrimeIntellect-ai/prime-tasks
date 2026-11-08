import wrong core-js module
### Describe the bug




there's no core-js module `es.symbol.async-dispose` but `esnext.symbol.async-dispose`

maybe also have others with wrong path

### Input code

```typescript
Symbol.asyncDispose
```


### Config

```json
{
  "jsc": {
    "parser": {
      "syntax": "typescript",
      "tsx": false
    },
    "target": "es2018",
    "loose": false,
    "minify": {
      "compress": false,
      "mangle": false
    },
    "externalHelpers":false
  },
  "module": {
    "type": "es6"
  },
  "minify": false,
  "isModule": true,
  "env": {
    "mode": "usage",
    "coreJs": "3.29"
  }
}
```


### Playground link

https://play.swc.rs/?version=1.3.66&code=H4sIAAAAAAAAA52STW%2BDMAyG7%2F0VLocKpArtDOK2nSdtu01TFRKjZssSlA9aVPHfBwlQ1A9tWi5Bzmv7MX7xWCttoXKSWq4k7HaEsUduamVIKfAFjXKaYoyy2UJDhMMtENNKmsBpBcAriH0U1kUB0gkBmw2cI43iDB6CNqhtW6OqFpJIlZ9IbZSA3Wt1AIkHeOtFT1orHUfP%2FhXwWPcXsjRKcl%2BrIRqY58R8Lr4gC2cIrl%2Fb71KJ1D%2BG0fBOsxtK4AakssCw4nLRfzhjfyjCOO830j%2BCupsR55yrv3PJy%2F6Cyv5Nye4AjguasvyKJnv8siRPMHtnhui9kxpL6FdaO7OPT4Ejm%2Bw0dsqmj9FgWbig81UGPhTDoJdrvqo%2BZlvdG%2BycrNE6LUPPfNX9AIz2hMn4AgAA&config=H4sIAAAAAAAAA21PXQrCMAx%2B9xQjzyI6QdQTiOAhSs1GpWtL0snG2N1tu3VT8C358v1l2BQFvFjCtRjCGBYniJGWPSDcGy%2B6gIDvHbIk5Txs89VzPFVCMyZonC7gBdXoowq53B%2FOswK0tYxZMWONMqrqvzOlbRwh8y8xUoWpNf5NxM4jGaFvqB1SkGZKIkBjn21Szo%2FGZ6Z6J1hJucmSCoofWempnTA079UoGCejlkWN%2BU1pCe%2BxPhx35SUFbMYPMjOtfW4BAAA%3D

### Expected behavior

correct core-js module path

### Actual behavior

_No response_

### Version

1.3.66

### Additional context

_No response_
