Add lang attribute to the brand component
**Is your feature request related to a problem? Please describe.**
We currently don't have a lang attribute defined for the Brand Component which would help screen readers to announce brand name in the correct accent. i.e `BBC News’ is announced with an English accent.

**Describe the solution you'd like**
Add a `lang` attribute to the `Brand` component.

**Describe alternatives you've considered**
N/A

**Testing notes**
[Tester to complete]

Dev insight: Will Cypress tests be required or are unit tests sufficient? Will there be any potential regression? etc

**Additional context**
Add any other context or screenshots about the feature request here.

### Additional contract requirements

- The `Brand` component takes the product name as its `product` prop and the optional localized service name as its `serviceLocalisedName` prop.
- When a localized service name is provided, the product name must carry English (United Kingdom) language metadata (`en-GB`) for screen readers, and the localized service name is announced after it.
- When no localized service name is provided, the announced text still includes the product name.
