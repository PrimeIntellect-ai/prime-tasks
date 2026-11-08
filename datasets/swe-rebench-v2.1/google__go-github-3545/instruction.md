Support for registry_package events
According to the [documentation](https://docs.github.com/en/webhooks/webhook-events-and-payloads#registry_package) (and [this](https://docs.github.com/en/webhooks/webhook-events-and-payloads#package)) a Github App wishing to receive events for a new/updated package should expect to receive the package event which is the renamed registry_package event. However, what actually happens is that in the permissions section for a Github App there is only the Registry Packages event available and the webhook request title has the value `registry_package`.

Can we please add support for this?

### Additional contract requirements

Add a public event type `RegistryPackageEvent` in package `github` representing the `registry_package` webhook event. Parsing a webhook whose event title is `registry_package` must yield a `*RegistryPackageEvent`.

The type must expose the exported fields `Action *string`, `RegistryPackage *Package`, `Repository *Repository`, `Organization *Organization`, `Enterprise *Enterprise`, `Sender *User`, and `Installation *Installation`.

`RegistryPackageEvent` must expose the following accessor methods:

- `GetAction() string` — returns the event action value, or the empty string when the receiver or the action is nil.
- `GetEnterprise() *Enterprise` — returns the associated enterprise, or nil when absent.
- `GetInstallation() *Installation` — returns the associated installation, or nil when absent.
- `GetOrganization() *Organization` — returns the associated organization, or nil when absent.
- `GetRegistryPackage() *Package` — returns the associated registry package, or nil when absent.
- `GetRepository() *Repository` — returns the associated repository, or nil when absent.
- `GetSender() *User` — returns the associated sender, or nil when absent.

Each accessor must handle a nil receiver by returning its zero value (the empty string or nil).
