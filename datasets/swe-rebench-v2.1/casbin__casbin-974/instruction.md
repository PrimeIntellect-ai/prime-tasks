[Feature] I want to get the current domains
t seems that there is no API for getdomains. Would you like to add it? Because the adapter is implemented with MySQL

### Additional contract requirements

- Add an Enforcer API named `GetAllDomains() ([]string, error)` that returns the complete set of distinct domain names known to the current Enforcer. Return an error if retrieving the domains fails.
