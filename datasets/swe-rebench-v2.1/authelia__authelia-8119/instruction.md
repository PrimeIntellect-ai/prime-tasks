PSL updates
### Description


PSL (https://publicsuffix.org/) updates are extremely behind in authelia. Domains removed from the list may take months to become eligeble for protection under authelia. Can the list be updated on each authelia build?



### Use Case


A domain is listed on PSL. The domain is removed, authelia should acknowledge that.

### Details


_No response_

### Documentation


_No response_

### Pre-Submission Checklist


- [X] I agree to follow the [Code of Conduct](http://www.authelia.com/code-of-conduct)

- [X] I have checked for related issues and checked the documentation

### Additional contract requirements

- The public suffix list used to validate cookie domains must be kept current, so that a domain that has been removed from the Public Suffix List is no longer treated as a public suffix.
- Add a function `isCookieDomainAPublicSuffix(domain string) bool` in the package `internal/configuration/validator` that reports whether the given cookie domain is a public suffix. A leading dot in the domain is ignored.
