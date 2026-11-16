Implement Admin Domain Allows API
Mastodon's Admin Domain Allows API allows an admin to configure which domains are allowed to federate. The goal of this task is to implement the following endpoints of this API in BigBone:

- List all allowed domains
- Get a single allowed domain
- Allow a domain to federate
- Delete an allowed domain

The Admin Domain Allows API as it is documented by Mastodon can be found here:
https://docs.joinmastodon.org/methods/admin/domain_allows/

Tip: A lot of other endpoints similar to this have already been implemented. In order to get an idea how to implement this, I suggest that you study the code upfront. Start with one of the `*Methods.kt` files.

Please consult the following documents to make sure your contribution meets our projects criteria:

- [Code of Conduct](https://github.com/andregasser/bigbone/blob/master/CODE_OF_CONDUCT.md)
- [Code Contribution Guidelines](https://github.com/andregasser/bigbone/blob/master/CONTRIBUTING.md)

### Additional contract requirements

Expose these operations on `AdminDomainAllowMethods`: `getAllAllowedDomains(range: Range = Range())` to list allowed domains, `getAllowedDomain(id: String)` to retrieve one, `allowDomainToFederate(domain: String)` to add one, and `removeAllowedDomain(id: String)` to delete one. The listing operation must honor the supplied pagination range.
