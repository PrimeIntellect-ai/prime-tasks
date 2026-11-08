`sans-serif` not `sans serif`
**Is your feature request related to a problem? Please describe.**
https://github.com/bbc/psammead/blob/956c5f71ff7aa2624382fbd4731132748e746e86/packages/utilities/psammead-styles/src/font-families.js#L44
https://github.com/bbc/psammead/blob/956c5f71ff7aa2624382fbd4731132748e746e86/packages/utilities/psammead-styles/src/font-families.js#L65

**Describe the solution you'd like**
- `sans-serif`
- Bumping all psammead packages to use `sans-serif`

**Describe alternatives you've considered**
Keeping the invalid CSS

**Testing notes**
[Tester to complete]

Dev insight: Will Cypress tests be required or are unit tests sufficient? Will there be any potential regression? etc

**Additional context**
Add any other context or screenshots about the feature request here.

### Additional contract requirements

- Correct the generic family spelling in font-family values produced by the shared Psammead styles package, so those values use `sans-serif`. This shared-styles correction is the requested scope; it does not require independent changes to every package or package-version bumps.
