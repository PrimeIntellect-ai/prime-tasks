False positives with German mobile phone numbers
**Describe the bug**
Mobile phone numbers in Germany start with a `0` prefix such as 0157xxxxxxx. However the preceding `0` is dropped if the country code prefix `+49` is added. This is described [on this wikipedia page](https://de.wikipedia.org/wiki/Telefonvorwahl_(Deutschland)). Therefore [the related change made a while ago](https://github.com/validatorjs/validator.js/pull/933/files) is not restrictive enough.


**Examples**
invalid:
 '+49015123456789'
valid:
 '+4915123456789'

**Additional context**
Validator.js version: 13.6.0
Node.js version: v12.15.0
OS platform: macOS
