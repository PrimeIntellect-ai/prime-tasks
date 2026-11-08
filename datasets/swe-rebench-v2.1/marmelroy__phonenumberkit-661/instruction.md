Parsing doesn't work properly updating from 3.5.10 to 3.6.1
### New Issue Checklist

- [x] Updated PhoneNumberKit to the latest version / Specified the podspec directly from the repo
- [X] Phone number formatted correctly on [JavaScript version](https://htmlpreview.github.io/?https://github.com/google/libphonenumber/blob/master/javascript/i18n/phonenumbers/demo-compiled.html)
- [x] I searched for [existing GitHub issues](https://github.com/marmelroy/PhoneNumberKit)

### Steps to reproduce
```swift
let kit = PhoneNumberKit()
let kitNumber = try kit.parse("420777666555", withRegion: "CZ")
let formattedNumber = kit.format(kitNumber, toType: .international)
XCTAssertEqual(formattedNumber, "+420 777 666 555")
```

##### Expected result

Assert succeed

##### Actual result

It fails with: `PhoneNumberKit.PhoneNumberError.invalidNumber`

### Environment

- Integration through SPM - version `3.6.1`
- Xcode 14.3.1


### Notes

- Our tests caught it - it worked properly on `3.5.10`
