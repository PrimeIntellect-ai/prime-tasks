[BUG] CountryID Rendering PROFILE_MINIMUM
**Describe the bug**
There is an issue with the countryID of the profile; no matter what I do, the 2-letter code does not appear.

```xml
<ram:PostalTradeAddress>
          <ram:CountryID>XX</ram:CountryID>
</ram:PostalTradeAddress>
```
 This renders as:
```xml
<ram:PostalTradeAddress/>
```
