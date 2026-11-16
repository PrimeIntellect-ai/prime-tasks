ui:emptyValue=null does not work with number inputs
### Prerequisites

- [x] I have read the [documentation](https://react-jsonschema-form.readthedocs.io/);
- [x] In the case of a bug report, I understand that providing a [SSCCE](http://sscce.org/) example is tremendously useful to the maintainers.
- [x] Ideally, I'm providing a [sample JSFiddle](https://jsfiddle.net/n1k0/f2y3fq7L/6/) or a [shared playground link](https://mozilla-services.github.io/react-jsonschema-form/) demonstrating the issue.

### Description

Using ui:emptyValue=`null` with a type=`["number", "null"]` property doesn't actually give you null back. This appears to be an issue with when [HIDDEN].

### Steps to Reproduce

Make the age field empty. With the default widgets and current state, this is impossible, but it would be possible if `asNumber` is fixed. I have a custom Widget that passes null up thru `onChange` that reproduces this as well.

[Playground Link](https://mozilla-services.github.io/react-jsonschema-form/#eyJmb3JtRGF0YSI6eyJmaXJzdE5hbWUiOiJDaHVjayIsImxhc3ROYW1lIjoiTm9ycmlzIiwiYWdlIjowLCJiaW8iOm51bGwsInBhc3N3b3JkIjoibm9uZWVkIn0sInNjaGVtYSI6eyJ0aXRsZSI6IkEgcmVnaXN0cmF0aW9uIGZvcm0gKG51bGxhYmxlKSIsImRlc2NyaXB0aW9uIjoiQSBzaW1wbGUgZm9ybSBleGFtcGxlIHVzaW5nIG51bGxhYmxlIHR5cGVzIiwidHlwZSI6Im9iamVjdCIsInJlcXVpcmVkIjpbImZpcnN0TmFtZSIsImxhc3ROYW1lIl0sInByb3BlcnRpZXMiOnsiZmlyc3ROYW1lIjp7InR5cGUiOiJzdHJpbmciLCJ0aXRsZSI6IkZpcnN0IG5hbWUiLCJkZWZhdWx0IjoiQ2h1Y2sifSwibGFzdE5hbWUiOnsidHlwZSI6InN0cmluZyIsInRpdGxlIjoiTGFzdCBuYW1lIn0sImFnZSI6eyJ0eXBlIjpbImludGVnZXIiLCJudWxsIl0sInRpdGxlIjoiQWdlIn0sImJpbyI6eyJ0eXBlIjpbInN0cmluZyIsIm51bGwiXSwidGl0bGUiOiJCaW8ifSwicGFzc3dvcmQiOnsidHlwZSI6InN0cmluZyIsInRpdGxlIjoiUGFzc3dvcmQiLCJtaW5MZW5ndGgiOjN9LCJ0ZWxlcGhvbmUiOnsidHlwZSI6InN0cmluZyIsInRpdGxlIjoiVGVsZXBob25lIiwibWluTGVuZ3RoIjoxMH19fSwidWlTY2hlbWEiOnsiZmlyc3ROYW1lIjp7InVpOmF1dG9mb2N1cyI6dHJ1ZSwidWk6ZW1wdHlWYWx1ZSI6IiJ9LCJhZ2UiOnsidWk6d2lkZ2V0IjoidXBkb3duIiwidWk6dGl0bGUiOiJBZ2Ugb2YgcGVyc29uIiwidWk6ZGVzY3JpcHRpb24iOiIoZWFydGhpYW4geWVhcikiLCJ1aTplbXB0eVZhbHVlIjpudWxsfSwiYmlvIjp7InVpOndpZGdldCI6InRleHRhcmVhIiwidWk6cGxhY2Vob2xkZXIiOiJMZWF2aW5nIHRoaXMgZmllbGQgZW1wdHkgd2lsbCBjYXVzZSBmb3JtRGF0YSBwcm9wZXJ0eSB0byBiZSBgbnVsbGAiLCJ1aTplbXB0eVZhbHVlIjpudWxsfSwicGFzc3dvcmQiOnsidWk6d2lkZ2V0IjoicGFzc3dvcmQiLCJ1aTpoZWxwIjoiSGludDogTWFrZSBpdCBzdHJvbmchIn0sImRhdGUiOnsidWk6d2lkZ2V0IjoiYWx0LWRhdGV0aW1lIn0sInRlbGVwaG9uZSI6eyJ1aTpvcHRpb25zIjp7ImlucHV0VHlwZSI6InRlbCJ9fX19)

#### Expected behavior

For the value in formData to be `null`.

#### Actual behavior

The value in formData is `0`.

### Version

1.4.1
