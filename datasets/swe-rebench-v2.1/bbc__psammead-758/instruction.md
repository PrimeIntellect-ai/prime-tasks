Allow restricting inputProvider services
**Is your feature request related to a problem? Please describe.**
Currently the input provider provides all 40-something services. This isn't ideal as you cant use it to toggle variants of a component as you may not have all the config (e.g. footer) or assets (.e.g svgs)

**Describe the solution you'd like**
Add a 3rd argument to `inputProvider()` which is an array of services. It should then filter out unwanted services from its drop down.

**Testing notes**
[Tester to complete]

Dev insight: Test in storybook, a story will have a restricted list of services to pick.

**Additional context**
Add any other context or screenshots about the feature request here.
