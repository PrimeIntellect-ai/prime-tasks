Allow async `xit`
- [x] I have read [CONTRIBUTING](https://github.com/Quick/Quick/blob/main/CONTRIBUTING.md) and have done my best to follow them.

### What did you do?

It is currently not possible to `xit` an async test.

![Screenshot 2023-06-01 at 13 07 16](https://github.com/Quick/Quick/assets/6216959/dda5b7a8-0487-4879-92ff-54ba264b4237)

[HIDDEN]

### What did you expect to happen?

It compiles and the test is skipped

### What actually happened instead?

Compile time error

### Environment

List the software versions you're using:

 - Quick: `7.0.0`
 - Nimble: `N/A`
 - Xcode Version: `14.3`
 - Swift Version: `5.8`

Please also mention which package manager you used and its version. Delete the
other package managers in this list:

 - CocoaPods: `N/A`
 - Carthage: `N/A`
 - Swift Package Manager: `N/A`

### Project that demonstrates the issue

Please link to a project we can download that reproduces the issue. Feel free
to delete this section if it's not relevant to the issue (eg - feature request).

The project should be [short, self-contained, and correct example](http://sscce.org/).

### Additional contract requirements

- An asynchronous test declared with `xit` must compile and be skipped rather than executed.
