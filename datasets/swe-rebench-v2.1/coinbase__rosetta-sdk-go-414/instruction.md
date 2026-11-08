Support parse sub account as optional
**Is your feature request related to a problem? Please describe.**
<!-- Describe what the problem is. For example, “I'm always frustrated when [...]”. -->

As of the parser of SDK, the sub account is either required or not.  There is no option to make subaccount field as optional.

**Describe the solution you'd like**
<!-- Describe what you want to happen. -->
A flag to parse account with subaccount string as optional.

**Describe alternatives you've considered**
<!-- Describe any alternative solutions or features you've considered. -->

**Additional context**
<!-- Add any other context or screenshots about the feature request in this section. -->

### Additional contract requirements

Expose an account-matching option named `SubAccountOptional`. When enabled, an account identifier without a subaccount may match a description that otherwise requires a subaccount.
