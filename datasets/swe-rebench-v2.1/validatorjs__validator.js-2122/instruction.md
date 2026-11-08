isDataURI: is not matching valid MIME types with an underscore
**Describe the bug**
isDataURI will return false for MIME types, that have an underscore in them
Same issue as #2119

**Examples**
(bit of a faux example, as the base64 part is not really a "real" `application/media_control+xml` type file, but that is beyond the point here, as we only care for the MIME type part here)

```
data:application/media_control+xml;base64,iVBORw0KGgoAAAANSUhEUgAAAAgAAAAIBAMAAAA2IaO4AAAAFVBMVEXk5OTn5+ft7e319fX29vb5+fn///++GUmVAAAALUlEQVQIHWNICnYLZnALTgpmMGYIFWYIZTA2ZFAzTTFlSDFVMwVyQhmAwsYMAKDaBy0axX/iAAAAAElFTkSuQmCC
```
should return `true`, but currently returns `false`

I'll send a PR to fix this in a few moments
